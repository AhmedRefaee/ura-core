import 'package:firebase_ai/firebase_ai.dart';

/// Everything the model is told, kept in one place. The same rules are
/// duplicated in the `voice-match-items` edge function, which stays deployed as
/// a fallback — if you change them here, change them there too, or the two
/// implementations will start disagreeing about the same message.
class ItemMatchPrompt {
  const ItemMatchPrompt._();

  // Requests arrive as forwarded chat messages, so the model has to throw away
  // the conversation around the order before it starts matching.
  static const _textOpening =
      'You read a written order request — typically a WhatsApp message from '
      'someone at an outside entity, pasted in by the person handling it — and '
      'match what it asks for to items in a fixed inventory list. The message is '
      'primarily Arabic (Modern Standard Arabic or a regional dialect such as '
      'Gulf, Levantine, or Egyptian), and may include some English item or brand '
      'names mixed in — do not assume it is in English. Read the ENTIRE message '
      'and extract every distinct item and quantity it requests, not just the '
      'first one; one message may list many items. '
      'Real messages are messy. IGNORE everything that is not part of the order: '
      'greetings and pleasantries, thanks and sign-offs, sender names, phone '
      'numbers, addresses, timestamps, forwarded-message headers, quoted replies, '
      'emoji, and any line that does not name a product. Do not treat a person, '
      'a company, or a place as an item. '
      'Quantities may be written as Western digits (3), Arabic-Indic digits (٣), '
      'or words (ثلاثة); numbering that is only a list marker (1. 2. 3.) is NOT a '
      'quantity. A requested item with no quantity anywhere means 1. ';

  static const _sharedRules =
      'Identify every item you return by the integer ref of its line in the '
      'inventory list below. Never invent a ref that is not in the list, and '
      'never answer with a name where a ref is asked for. Parse a '
      'quantity for each requested item. If a phrase does not clearly correspond '
      'to any item in the list, put it in "unmatched" with the raw phrase instead of '
      'forcing a bad match. '
      'If a phrase does not fully specify which of several distinct '
      'inventory rows is meant, do NOT guess one of them and do NOT put it in '
      '"unmatched" — instead put it in "ambiguous" with the raw phrase, the '
      'parsed quantity/unit, and the ref of every plausible candidate row '
      '(2 to 4 candidates, most-likely-first). This applies to ANY missing '
      'distinguishing attribute, not just size — for example: (a) the request '
      'names a brand but not a size/packaging (e.g. "Nova water" when the '
      'inventory has both a 330ml and a 500ml Nova water row); (b) the request '
      'names a size/type but not a brand (e.g. "250ml water" when the inventory '
      'has 250ml water rows from more than one brand); or any other case where '
      'the words alone do not narrow it down to one specific row. Only '
      'use "ambiguous" when multiple rows genuinely match what was requested; a '
      'single clear match still goes in "matches". '
      'Also return a short natural-language "heard_summary" (in '
      'Arabic) recapping everything you understood from the request, so the person '
      'reviewing it can sanity-check it. Keep it to one sentence of at most 20 '
      'words — it is generated after everything else, so every extra word is '
      'time the person is watching a spinner. Do not list the items again one '
      'by one; they are already on the screen underneath it.';

  static const textInstruction = _textOpening + _sharedRules;

  /// The model answers in refs, never in ids — see [ItemMatchCatalog].
  static final Schema responseSchema = Schema.object(
    properties: {
      'matches': Schema.array(
        items: Schema.object(
          properties: {
            'item_ref': Schema.integer(),
            'quantity': Schema.number(),
            'confidence': Schema.number(),
          },
        ),
      ),
      'unmatched': Schema.array(
        items: Schema.object(
          properties: {
            'text': Schema.string(),
            'quantity': Schema.number(),
            'unit': Schema.string(),
          },
          optionalProperties: ['quantity', 'unit'],
        ),
      ),
      'ambiguous': Schema.array(
        items: Schema.object(
          properties: {
            'text': Schema.string(),
            'quantity': Schema.number(),
            'unit': Schema.string(),
            'candidate_item_refs': Schema.array(items: Schema.integer()),
          },
          optionalProperties: ['quantity', 'unit'],
        ),
      ),
      'heard_summary': Schema.string(),
    },
    optionalProperties: ['heard_summary'],
  );
}
