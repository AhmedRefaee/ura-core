import { createClient } from 'jsr:@supabase/supabase-js@2';

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');
// A multimodal model capable of native audio understanding — required since
// we send the recording itself, not a pre-transcribed string.
const GEMINI_MODEL = 'gemini-3.6-flash';

// Generous enough for a long forwarded WhatsApp thread, small enough that a
// pasted novel can't run up a Gemini bill. This function still has no rate
// limiting, so the cap is the only guard on the text surface.
const MAX_TEXT_CHARS = 4000;

/// The request being matched: either a recording to listen to, or a written
/// message to read. Everything downstream of the Gemini call is identical.
type MatchInput =
  | { kind: 'audio'; audioBase64: string; mimeType: string }
  | { kind: 'text'; text: string };

interface InventoryRow {
  id: string;
  item_name: string;
  sku: string | null;
  category: string | null;
  unit: string;
}

interface MatchResponse {
  matches: { item_id: string; quantity: number; confidence: number }[];
  unmatched: { text: string; quantity?: number; unit?: string }[];
  ambiguous: { text: string; quantity?: number; unit?: string; candidate_item_ids: string[] }[];
  heard_summary?: string;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const t0 = Date.now();
  try {
    const payload = await req.json();
    const audioBase64 = typeof payload.audio_base64 === 'string' ? payload.audio_base64.trim() : '';
    const text = typeof payload.text === 'string' ? payload.text.trim() : '';
    const mimeType = payload.mime_type;

    if (audioBase64 && text) {
      return jsonResponse({ error: 'Provide either audio_base64 or text, not both' }, 400);
    }
    // No usable input at all is not an error — an empty recording already
    // returned an empty result, and the paste screen relies on the same.
    if (!audioBase64 && !text) {
      return jsonResponse({ matches: [], unmatched: [] });
    }
    if (audioBase64 && (!mimeType || typeof mimeType !== 'string')) {
      return jsonResponse({ error: 'Missing mime_type' }, 400);
    }
    if (text.length > MAX_TEXT_CHARS) {
      return jsonResponse({ error: `Text exceeds ${MAX_TEXT_CHARS} characters` }, 400);
    }

    const input: MatchInput = text
      ? { kind: 'text', text }
      : { kind: 'audio', audioBase64, mimeType };

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
      .is('archived_at', null);

    if (error) throw error;
    if (!inventory || inventory.length === 0) {
      return jsonResponse({ matches: [], unmatched: [] });
    }
    const t1 = Date.now();

    const result = await matchWithGemini(input, inventory as InventoryRow[]);
    const t2 = Date.now();
    // Temporary instrumentation to find where request latency actually goes —
    // surfaces in the client's debug log via ItemMatchRepository, since that's
    // the only practical log visibility available without extra tooling.
    const debugTimingMs = {
      inventory_fetch: t1 - t0,
      gemini_call: t2 - t1,
      total: t2 - t0,
    };

    // Defense in depth: never trust the model's ids blindly — only ids that
    // actually exist in the org's own inventory (just fetched under RLS)
    // are allowed through.
    const validIds = new Set((inventory as InventoryRow[]).map((i) => i.id));
    const matches = result.matches.filter((m) => validIds.has(m.item_id) && m.quantity > 0);
    const unmatched = [...result.unmatched];
    const ambiguous: typeof result.ambiguous = [];

    for (const entry of result.ambiguous ?? []) {
      const candidateIds = entry.candidate_item_ids.filter((id) => validIds.has(id)).slice(0, 4);
      if (candidateIds.length >= 2) {
        ambiguous.push({ ...entry, candidate_item_ids: candidateIds });
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
    return jsonResponse({ error: message }, 500);
  }
});

const AUDIO_OPENING =
  'You listen to an audio recording of someone dictating an order request, ' +
  'and match what they say to items in a fixed inventory list. The speech is ' +
  'primarily Arabic (Modern Standard Arabic or a regional dialect such as ' +
  'Gulf, Levantine, or Egyptian), and may include some English item or brand ' +
  'names mixed in — do not assume the audio is in English. Listen to the ' +
  'ENTIRE recording from start to finish and extract every distinct item and ' +
  'quantity mentioned, not just the first one; the speaker may list many items ' +
  'in one recording. ';

// Written requests reach the verifier as forwarded chat messages, so the
// model has to do something the audio path never needed: throw away the
// conversation around the order before it starts matching.
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
  'You MUST only return item_id values that appear in the provided inventory ' +
  'list below — never invent an id or a name that is not in the list. Parse a ' +
  'quantity for each requested item. If a phrase does not clearly correspond ' +
  'to any item in the list, put it in "unmatched" with the raw phrase instead of ' +
  'forcing a bad match. ' +
  'If a phrase does not fully specify which of several distinct ' +
  'inventory rows is meant, do NOT guess one of them and do NOT put it in ' +
  '"unmatched" — instead put it in "ambiguous" with the raw phrase, the ' +
  'parsed quantity/unit, and the item_id of every plausible candidate row ' +
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

async function matchWithGemini(
  input: MatchInput,
  inventory: InventoryRow[],
): Promise<MatchResponse> {
  if (!GEMINI_API_KEY) throw new Error('GEMINI_API_KEY not configured');

  const inventoryContext = inventory.map((i) => ({
    id: i.id,
    name: i.item_name,
    sku: i.sku,
    category: i.category,
    unit: i.unit,
  }));

  const systemInstruction = (input.kind === 'audio' ? AUDIO_OPENING : TEXT_OPENING) + SHARED_RULES;

  const body = {
    systemInstruction: { parts: [{ text: systemInstruction }] },
    contents: [
      {
        role: 'user',
        parts: [
          {
            text:
              'Inventory (JSON array of {id, name, sku, category, unit}):\n' +
              JSON.stringify(inventoryContext),
          },
          input.kind === 'text'
            ? { text: 'Request message:\n' + input.text }
            : { inlineData: { mimeType: input.mimeType, data: input.audioBase64 } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: {
        type: 'OBJECT',
        properties: {
          matches: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                item_id: { type: 'STRING' },
                quantity: { type: 'NUMBER' },
                confidence: { type: 'NUMBER' },
              },
              required: ['item_id', 'quantity', 'confidence'],
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
                candidate_item_ids: { type: 'ARRAY', items: { type: 'STRING' } },
              },
              required: ['text', 'candidate_item_ids'],
            },
          },
          heard_summary: { type: 'STRING' },
        },
        required: ['matches', 'unmatched', 'ambiguous'],
      },
    },
  };

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': GEMINI_API_KEY,
      },
      body: JSON.stringify(body),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Gemini request failed: ${response.status} ${text}`);
  }

  const data = await response.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error('Gemini returned no content');

  const parsed = JSON.parse(text) as MatchResponse;
  return {
    matches: Array.isArray(parsed.matches) ? parsed.matches : [],
    unmatched: Array.isArray(parsed.unmatched) ? parsed.unmatched : [],
    ambiguous: Array.isArray(parsed.ambiguous) ? parsed.ambiguous : [],
    heard_summary: typeof parsed.heard_summary === 'string' ? parsed.heard_summary : undefined,
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
