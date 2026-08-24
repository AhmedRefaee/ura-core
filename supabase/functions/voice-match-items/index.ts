import { createClient } from 'jsr:@supabase/supabase-js@2';

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');
// Kept in step with the Dart path's model choice. This function is the unused
// fallback; the app calls Gemini directly. See DirectItemMatchRepository.
const GEMINI_MODEL = 'gemini-3.6-flash';
// This is an extraction task, not a reasoning one: read a request, find the
// names in a list, return quantities. gemini-3.6-flash thinks at "medium" by
// default, and thinking tokens are billed AND waited on like output tokens —
// so the default was buying latency this job doesn't need. "low" keeps enough
// deliberation for the ambiguous-candidate judgement; "minimal" is the next
// step down if that judgement still holds up in testing.
const THINKING_LEVEL = 'low';
// This model is new enough to be capacity-constrained: under load it answers
// 503 UNAVAILABLE ("high demand"), and — worse — it can hold the connection
// open for a minute or more before saying so. Google's own client SDKs retry
// that class of error transparently; a bare fetch gets none of that, so a
// demand spike on their side reached the verifier as an 80-second wait and a
// dead end. Everything below exists to bound that.
const GEMINI_FALLBACK_MODEL = 'gemini-3.5-flash';
const GEMINI_MAX_ATTEMPTS = 3;
// Per attempt, so a hung endpoint gets abandoned and retried instead of waited
// out. A text request that hasn't answered in 20s is not going to.
const TEXT_ATTEMPT_TIMEOUT_MS = 20_000;
// Ceiling across all attempts and backoffs. Someone is standing there holding a
// phone: past this it is kinder to say "busy, try again" than to keep spinning.
const TOTAL_BUDGET_MS = 55_000;
const BACKOFF_BASE_MS = 700;
// Worth asking again: overload, rate limiting, gateway hiccups. A 400 or a 403
// means the request or the key is wrong, and repeating it only burns the
// caller's remaining budget.
const RETRYABLE_STATUSES = new Set([408, 429, 500, 502, 503, 504]);

/// Every attempt failed for a reason that might not repeat. Kept distinct from
/// a genuine bug so the client can tell the verifier "try again in a moment"
/// and actually mean it.
class UpstreamBusyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UpstreamBusyError';
  }
}

// The web build calls this from a browser, which preflights it because the
// request carries an Authorization header and a JSON body. Without these
// headers — and without answering OPTIONS below — the call never leaves the
// browser and surfaces as an opaque "Failed to fetch". Origin is not the
// access boundary here: every request still needs a valid JWT, and the
// inventory query runs under it so RLS decides what the caller can see.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

// Generous enough for a long forwarded WhatsApp thread, small enough that a
// pasted novel can't run up a Gemini bill. This function still has no rate
// limiting, so the cap is the only guard on the text surface.
const MAX_TEXT_CHARS = 4000;

interface InventoryRow {
  id: string;
  item_name: string;
  sku: string | null;
  category: string | null;
  unit: string;
}

/// What Gemini answers with. It names items by the short catalog ref it was
/// given, never by id — see buildCatalog.
interface MatchResponse {
  matches: { item_ref: number; quantity: number; confidence: number }[];
  unmatched: { text: string; quantity?: number; unit?: string }[];
  ambiguous: { text: string; quantity?: number; unit?: string; candidate_item_refs: number[] }[];
  heard_summary?: string;
}

/// What the client gets back — real inventory ids, unchanged from before the
/// refs existed.
interface MatchOut {
  item_id: string;
  quantity: number;
  confidence: number;
}

interface AmbiguousOut {
  text: string;
  quantity?: number;
  unit?: string;
  candidate_item_ids: string[];
}

/// Only the parts of Gemini's response envelope this function reads.
interface GeminiResponse {
  candidates?: { content?: { parts?: { text?: string }[] } }[];
  usageMetadata?: UsageMetadata;
}

/// Response token accounting. Thinking tokens are reported separately from
/// output tokens but bill and cost latency the same way, which is the whole
/// reason they're worth surfacing.
interface UsageMetadata {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  thoughtsTokenCount?: number;
  cachedContentTokenCount?: number;
}

Deno.serve(async (req) => {
  // Answer the browser's preflight before anything else — it arrives as
  // OPTIONS, which the method check below would otherwise reject as 405.
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const t0 = Date.now();
  try {
    const payload = await req.json();
    const text = typeof payload.text === 'string' ? payload.text.trim() : '';

    // No usable input is not an error — the paste screen warms this function
    // with an empty body precisely because it returns before doing any work.
    if (!text) {
      return jsonResponse({ matches: [], unmatched: [] });
    }
    if (text.length > MAX_TEXT_CHARS) {
      return jsonResponse({ error: `Text exceeds ${MAX_TEXT_CHARS} characters` }, 400);
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse({ error: 'Missing authorization' }, 401);
    }

    // Runs with the caller's JWT so this query stays under the same
    // Postgres RLS (auth_org_id()) as every other client request — no
    // service-role key, no new cross-org access surface.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: inventory, error } = await supabase
      .from('inventory')
      .select('id, item_name, sku, category, unit')
      .is('archived_at', null)
      // Stable order keeps the catalog block byte-identical from one call to
      // the next while the inventory itself doesn't change, which is what
      // gives Gemini's implicit caching a prefix to hit. Postgres promises no
      // ordering without this.
      .order('id');

    if (error) throw error;
    if (!inventory || inventory.length === 0) {
      return jsonResponse({ matches: [], unmatched: [] });
    }
    const catalog = buildCatalog(inventory as InventoryRow[]);
    const t1 = Date.now();

    const { result, usage, model, attempts } = await matchWithGemini(
      text,
      catalog.block,
      t0 + TOTAL_BUDGET_MS,
    );
    const t2 = Date.now();
    // Temporary instrumentation to find where request latency actually goes —
    // surfaces in the client's debug log via ItemMatchRepository, since that's
    // the only practical log visibility available without extra tooling. The
    // token counts are here for the same reason: prompt_tokens is what the
    // compact catalog buys, cached_tokens says whether the stable prefix is
    // hitting, and thinking_tokens is the number to watch when tuning
    // THINKING_LEVEL — they bill and cost latency like output tokens.
    const debugTimingMs = {
      inventory_fetch: t1 - t0,
      gemini_call: t2 - t1,
      total: t2 - t0,
      catalog_chars: catalog.block.length,
      prompt_tokens: usage.promptTokenCount,
      cached_tokens: usage.cachedContentTokenCount,
      thinking_tokens: usage.thoughtsTokenCount,
      output_tokens: usage.candidatesTokenCount,
      // Which model actually answered and how many tries it took — together
      // they say whether the primary model is carrying its own weight.
      gemini_model: model,
      gemini_attempts: attempts,
    };

    // The ref table doubles as the allow-list it replaces: a ref the model
    // invented was never issued, so it resolves to nothing and can't reach the
    // client. Same defense in depth as the old id check, one lookup instead.
    const matches: MatchOut[] = [];
    for (const match of result.matches) {
      const itemId = catalog.idByRef(match.item_ref);
      if (itemId && match.quantity > 0) {
        matches.push({ item_id: itemId, quantity: match.quantity, confidence: match.confidence });
      }
    }
    const unmatched = [...result.unmatched];
    const ambiguous: AmbiguousOut[] = [];

    for (const entry of result.ambiguous ?? []) {
      const candidateIds = [
        // Deduped: the same row offered twice would render as two identical
        // choices in the review sheet, which reads as a bug.
        ...new Set(
          (entry.candidate_item_refs ?? [])
            .map((ref) => catalog.idByRef(ref))
            .filter((id): id is string => id !== undefined),
        ),
      ].slice(0, 4);
      if (candidateIds.length >= 2) {
        ambiguous.push({
          text: entry.text,
          quantity: entry.quantity,
          unit: entry.unit,
          candidate_item_ids: candidateIds,
        });
      } else if (candidateIds.length === 1) {
        // Nothing left to disambiguate — it's a real match.
        matches.push({ item_id: candidateIds[0], quantity: entry.quantity ?? 1, confidence: 1 });
      } else {
        // No valid candidates survived — falls back to unmatched.
        unmatched.push({ text: entry.text, quantity: entry.quantity, unit: entry.unit });
      }
    }

    return jsonResponse({
      matches,
      unmatched,
      ambiguous,
      heard_summary: result.heard_summary,
      debug_timing_ms: debugTimingMs,
    });
  } catch (err) {
    console.error('voice-match-items error', err);
    // Surface the real failure reason (Gemini errors, parsing errors, etc.)
    // instead of a generic message — this is what shows up in the client's
    // FunctionException.details, which is the only log visibility we have
    // without a separate log-fetching workflow.
    const message = err instanceof Error ? err.message : String(err);
    // 503 + retryable is the client's cue to say "busy, try again" rather than
    // the generic failure message, because here that advice actually works.
    const busy = err instanceof UpstreamBusyError;
    return jsonResponse({ error: message, retryable: busy }, busy ? 503 : 500);
  }
});

// Written requests reach the verifier as forwarded chat messages, so the model
// has to throw away the conversation around the order before it starts matching.
const TEXT_OPENING =
  'You read a written order request — typically a WhatsApp message from ' +
  'someone at an outside entity, pasted in by the person handling it — and ' +
  'match what it asks for to items in a fixed inventory list. The message is ' +
  'primarily Arabic (Modern Standard Arabic or a regional dialect such as ' +
  'Gulf, Levantine, or Egyptian), and may include some English item or brand ' +
  'names mixed in — do not assume it is in English. Read the ENTIRE message ' +
  'and extract every distinct item and quantity it requests, not just the ' +
  'first one; one message may list many items. ' +
  'Real messages are messy. IGNORE everything that is not part of the order: ' +
  'greetings and pleasantries, thanks and sign-offs, sender names, phone ' +
  'numbers, addresses, timestamps, forwarded-message headers, quoted replies, ' +
  'emoji, and any line that does not name a product. Do not treat a person, ' +
  'a company, or a place as an item. ' +
  'Quantities may be written as Western digits (3), Arabic-Indic digits (٣), ' +
  'or words (ثلاثة); numbering that is only a list marker (1. 2. 3.) is NOT a ' +
  'quantity. A requested item with no quantity anywhere means 1. ';

const SHARED_RULES =
  'Identify every item you return by the integer ref of its line in the ' +
  'inventory list below. Never invent a ref that is not in the list, and ' +
  'never answer with a name where a ref is asked for. Parse a ' +
  'quantity for each requested item. If a phrase does not clearly correspond ' +
  'to any item in the list, put it in "unmatched" with the raw phrase instead of ' +
  'forcing a bad match. ' +
  'If a phrase does not fully specify which of several distinct ' +
  'inventory rows is meant, do NOT guess one of them and do NOT put it in ' +
  '"unmatched" — instead put it in "ambiguous" with the raw phrase, the ' +
  'parsed quantity/unit, and the ref of every plausible candidate row ' +
  '(2 to 4 candidates, most-likely-first). This applies to ANY missing ' +
  'distinguishing attribute, not just size — for example: (a) the request ' +
  'names a brand but not a size/packaging (e.g. "Nova water" when the ' +
  'inventory has both a 330ml and a 500ml Nova water row); (b) the request ' +
  'names a size/type but not a brand (e.g. "250ml water" when the inventory ' +
  'has 250ml water rows from more than one brand); or any other case where ' +
  'the words alone do not narrow it down to one specific row. Only ' +
  'use "ambiguous" when multiple rows genuinely match what was requested; a ' +
  'single clear match still goes in "matches". ' +
  'Also return a short natural-language "heard_summary" (in ' +
  'Arabic) recapping everything you understood from the request, so the person ' +
  'reviewing it can sanity-check it.';

/// The inventory as the model sees it. Two things used to make this the most
/// expensive part of every request, and neither helps the model recognise an
/// Arabic product name: a 36-char UUID on each of ~200 rows (~17 tokens apiece,
/// and the id only ever has to survive the round trip intact), and the JSON
/// field names repeated on every one of those rows. So rows go out as
/// pipe-delimited lines keyed by a short integer ref, and `idByRef` turns the
/// model's answer back into real ids. Nothing outside this function sees a ref.
function buildCatalog(inventory: InventoryRow[]): {
  block: string;
  idByRef: (raw: unknown) => string | undefined;
} {
  const ids = new Map<number, string>();
  const lines = inventory.map((row, index) => {
    const ref = index + 1;
    ids.set(ref, row.id);
    return [ref, row.item_name, row.unit, row.category ?? '', row.sku ?? '']
      // A pipe or a newline inside a name would silently shift every field
      // after it onto the wrong column.
      .map((field) => String(field).replace(/[|\r\n]+/g, ' ').trim())
      .join('|');
  });
  return {
    block: 'Inventory — one item per line, as ref|name|unit|category|sku:\n' + lines.join('\n'),
    // The schema asks for an integer, but a model can still answer '12' or
    // 12.0. Anything that doesn't name a ref we actually issued resolves to
    // undefined, and the caller drops it.
    idByRef: (raw: unknown) => {
      const ref = typeof raw === 'number' ? raw : Number(String(raw ?? '').trim());
      return Number.isInteger(ref) ? ids.get(ref) : undefined;
    },
  };
}

async function matchWithGemini(
  text: string,
  catalogBlock: string,
  deadline: number,
): Promise<{ result: MatchResponse; usage: UsageMetadata; model: string; attempts: number }> {
  if (!GEMINI_API_KEY) throw new Error('GEMINI_API_KEY not configured');

  const systemInstruction = TEXT_OPENING + SHARED_RULES;

  const body = {
    systemInstruction: { parts: [{ text: systemInstruction }] },
    contents: [
      {
        role: 'user',
        parts: [
          // The catalog goes first and stays byte-identical between calls, so
          // it can serve as a cacheable prefix; the part that varies per
          // request follows it.
          { text: catalogBlock },
          { text: 'Request message:\n' + text },
        ],
      },
    ],
    generationConfig: {
      thinkingConfig: { thinkingLevel: THINKING_LEVEL },
      responseMimeType: 'application/json',
      responseSchema: {
        type: 'OBJECT',
        properties: {
          matches: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                item_ref: { type: 'INTEGER' },
                quantity: { type: 'NUMBER' },
                confidence: { type: 'NUMBER' },
              },
              required: ['item_ref', 'quantity', 'confidence'],
            },
          },
          unmatched: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                text: { type: 'STRING' },
                quantity: { type: 'NUMBER' },
                unit: { type: 'STRING' },
              },
              required: ['text'],
            },
          },
          ambiguous: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                text: { type: 'STRING' },
                quantity: { type: 'NUMBER' },
                unit: { type: 'STRING' },
                candidate_item_refs: { type: 'ARRAY', items: { type: 'INTEGER' } },
              },
              required: ['text', 'candidate_item_refs'],
            },
          },
          heard_summary: { type: 'STRING' },
        },
        required: ['matches', 'unmatched', 'ambiguous'],
      },
    },
  };

  const { data, model, attempts } = await callGemini(body, deadline);

  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error('Gemini returned no content');

  const parsed = JSON.parse(text) as MatchResponse;
  return {
    result: {
      matches: Array.isArray(parsed.matches) ? parsed.matches : [],
      unmatched: Array.isArray(parsed.unmatched) ? parsed.unmatched : [],
      ambiguous: Array.isArray(parsed.ambiguous) ? parsed.ambiguous : [],
      heard_summary: typeof parsed.heard_summary === 'string' ? parsed.heard_summary : undefined,
    },
    usage: (data.usageMetadata ?? {}) as UsageMetadata,
    model,
    attempts,
  };
}

/// The retry behavior Google's own client SDKs provide and a bare fetch does
/// not: bound every attempt with a timeout, back off between them, and stop
/// when the caller's time budget runs out rather than when some fixed count
/// does. The last attempt goes to the fallback model — if the primary is the
/// thing that's overloaded, asking it a third time is only a slower way to fail.
async function callGemini(
  body: unknown,
  deadline: number,
): Promise<{ data: GeminiResponse; model: string; attempts: number }> {
  const attemptTimeoutMs = TEXT_ATTEMPT_TIMEOUT_MS;
  let lastMessage = 'Gemini was never reached';

  for (let attempt = 1; attempt <= GEMINI_MAX_ATTEMPTS; attempt++) {
    const remainingMs = deadline - Date.now();
    if (remainingMs <= 0) break;
    const model = attempt === GEMINI_MAX_ATTEMPTS ? GEMINI_FALLBACK_MODEL : GEMINI_MODEL;

    const outcome = await attemptGemini(model, body, Math.min(attemptTimeoutMs, remainingMs));
    if ('data' in outcome) return { data: outcome.data, model, attempts: attempt };

    lastMessage = outcome.message;
    // Asking again cannot fix a malformed request or a bad key.
    if (!outcome.retryable) throw new Error(lastMessage);
    console.warn(`voice-match-items: ${model} attempt ${attempt} failed — ${lastMessage.slice(0, 200)}`);

    // Exponential, with jitter so one spike doesn't turn every waiting client
    // into a synchronized second wave.
    const backoffMs = BACKOFF_BASE_MS * 2 ** (attempt - 1) + Math.random() * 250;
    if (deadline - Date.now() <= backoffMs) break;
    await new Promise((resolve) => setTimeout(resolve, backoffMs));
  }

  throw new UpstreamBusyError(lastMessage);
}

/// One call. Sorts "this might work if we ask again" (our own timeout, a
/// dropped connection, overload, rate limiting) from "asking again won't help".
async function attemptGemini(
  model: string,
  body: unknown,
  timeoutMs: number,
): Promise<{ data: GeminiResponse } | { message: string; retryable: boolean }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': GEMINI_API_KEY!,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      },
    );

    if (!response.ok) {
      const text = await response.text();
      return {
        message: `Gemini request failed: ${response.status} ${text}`,
        retryable: RETRYABLE_STATUSES.has(response.status),
      };
    }
    return { data: (await response.json()) as GeminiResponse };
  } catch (err) {
    // Our own abort and a dropped connection are both worth another go.
    const aborted = err instanceof Error && err.name === 'AbortError';
    return {
      message: aborted
        ? `Gemini did not answer within ${timeoutMs}ms (${model})`
        : `Gemini call failed: ${err instanceof Error ? err.message : String(err)}`,
      retryable: true,
    };
  } finally {
    clearTimeout(timer);
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    // Errors need the CORS headers as much as successes do; without them a
    // browser reports a failed fetch instead of the real message.
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}
