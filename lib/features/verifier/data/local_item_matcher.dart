import 'dart:math';

import '../../../core/text/arabic_text.dart';
import '../../../shared/models/inventory_item.dart';
import 'english_alias.dart';

/// One inventory row this matcher thinks a request line might mean.
class ScoredItem {
  final InventoryItem item;

  /// 0 to 1. Not a probability — a ranking signal, calibrated only against
  /// other candidates for the same line.
  final double score;

  const ScoredItem(this.item, this.score);

  @override
  String toString() => '${item.itemName} (${score.toStringAsFixed(2)})';
}

/// One line of a request, and what the catalog might have to offer it.
class RequestLine {
  /// The line as the sender wrote it, list marker stripped. Shown to the
  /// verifier and used as the name if this becomes a custom item.
  final String text;

  /// How many were asked for. Defaults to 1, which is what a bare product name
  /// means in practice.
  final double quantity;

  /// Best first. Empty when nothing in the catalog scored at all.
  final List<ScoredItem> candidates;

  /// True only when the line is clearly not a request at all: a greeting, a
  /// sign-off, a phone number. Noise is dropped silently, so the test for it
  /// is deliberately narrow.
  ///
  /// It used to be "no word of this line is in the catalog", which quietly
  /// deleted every request for something not stocked — the sender asks for a
  /// vacuum cleaner and nobody ever learns they asked. Showing a greeting as
  /// an unmatched line costs one glance; losing a request costs an order.
  final bool isNoise;

  const RequestLine({
    required this.text,
    required this.quantity,
    required this.candidates,
    required this.isNoise,
  });

  ScoredItem? get best => candidates.isEmpty ? null : candidates.first;
}

/// Matches a written request against the inventory, on-device and offline.
///
/// The catalog is 194 rows. That is small enough to search directly, which is
/// worth saying plainly because the first version of this feature sent all 194
/// rows to Gemini on every single request and waited on it to write the answer
/// back one token at a time. Reading a fixed list is not a task that needs a
/// language model; ranking a phrase against a fixed list is what an index does.
///
/// What this deliberately does NOT do is decide anything. It ranks, and hands
/// the ranking up. Whether a score is good enough to add to an order, good
/// enough to offer as a choice, or bad enough to send to the model instead is
/// a policy question that lives above this class.
class LocalItemMatcher {
  final List<InventoryItem> _inventory;

  /// Folded token -> indices into [_inventory]. The whole point of the index:
  /// a line only ever scores rows that share a word with it.
  final Map<String, Set<int>> _postings = {};

  /// Folded token -> how much it narrows things down. "مياه" appears in dozens
  /// of rows and says almost nothing; "نوفا" or "330" points at a handful.
  final Map<String, double> _idf = {};

  /// Words from the item's own name. These are what a full match is measured
  /// against.
  final List<List<String>> _nameTokens = [];

  /// Words from category and SKU. They earn a row a place in the running —
  /// "قهوة" should surface the coffee rows — but they must not count towards
  /// coverage. "سحلب" is a one-word product sitting in the three-word category
  /// "مشروبات ساخنة أخرى"; measured against all four words, naming the product
  /// exactly and completely scored 0.34.
  final List<List<String>> _extraTokens = [];

  final List<double> _nameWeight = [];

  /// What a category or SKU hit is worth next to a name hit.
  static const _extraTokenWeight = 0.3;

  LocalItemMatcher(List<InventoryItem> inventory) : _inventory = inventory {
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      // The unit is deliberately excluded: "كرتونة" is how it is sold, not what
      // it is, and including it makes every row look alike.
      final name = ArabicText.tokenize(row.itemName);
      final extra = ArabicText.tokenize('${row.category ?? ''} ${row.sku ?? ''}')
          .where((t) => !name.contains(t))
          .toList();
      _nameTokens.add(name);
      _extraTokens.add(extra);
      for (final token in {...name, ...extra}) {
        _postings.putIfAbsent(token, () => <int>{}).add(i);
      }
    }

    final total = inventory.length;
    for (final entry in _postings.entries) {
      // No floor: a token present in every row narrows nothing and must be
      // worth nothing, or it caps every row's achievable coverage below 1.
      _idf[entry.key] = log((total + 1) / (entry.value.length + 1));
    }

    for (final tokens in _nameTokens) {
      _nameWeight.add(_weigh(tokens));
    }
  }

  /// What a full match on this row is worth, so coverage can be a fraction of
  /// it. Distinct tokens only: a name that repeats a word shouldn't be harder
  /// to satisfy than one that doesn't.
  double _weigh(List<String> tokens) {
    final weight = tokens.toSet().fold<double>(0, (sum, t) => sum + (_idf[t] ?? 0));
    // A row whose every word is universal has nothing to distinguish it. Guard
    // the division rather than letting it produce infinity.
    return weight > 0 ? weight : 1;
  }

  /// A token is worth matching only if it is a real word. Numbers are matched
  /// exactly and never fuzzily — 330 and 500 are one character apart and mean
  /// two different products.
  static final _numeric = RegExp(r'^\d+$');

  /// Units of measure that belong to the product name rather than to the order.
  /// "٣٣٠ مل" is a size; "٣ كرتونة" is a quantity.
  static const _sizeUnits = {
    'مل', 'لتر', 'ل', 'جم', 'جرام', 'غرام', 'كجم', 'كيلو', 'كيلوجرام',
    'ml', 'l', 'g', 'kg', 'gm', 'cc', 'سم', 'مم',
  };

  /// A leading list marker: "1." "2)" "3-" "1/" "-" "•". Numbering is not a
  /// quantity, and reading it as one turns a numbered list into escalating
  /// order sizes. "3-" is the form real senders actually use most, and it is
  /// the most dangerous: without it, "1- ٥ بكت شاي" orders one, not five.
  /// "1/" is just as common in English-language messages.
  static final _listMarker = RegExp(r'^\s*(?:[-*•·]|\d{1,2}\s*[-./)\]])\s+');

  static final _quantityToken = RegExp(r'^\d+(?:[.,]\d+)?$');

  /// Single letters Arabic attaches to the front of a word: and, then, with,
  /// for, like.
  static const _proclitics = {'و', 'ف', 'ب', 'ل', 'ك'};

  /// Senders put several items on one line separated by a comma as often as
  /// by a newline. Deliberately not splitting on "و" as well: it is a letter
  /// that begins real words, and splitting on it would cut names in half.
  static final _inlineSeparators = RegExp(r'[،؛;]|,(?=\s)');

  /// Splits [message] into request lines and ranks the catalog against each.
  List<RequestLine> match(String message) {
    final lines = <RequestLine>[];
    for (final rawLine in message.split('\n')) {
      for (final raw in rawLine.split(_inlineSeparators)) {
        final text = raw.replaceFirst(_listMarker, '').trim();
        if (text.isEmpty) continue;
        lines.add(_matchLine(text));
      }
    }
    return lines;
  }

  /// Words that only ever appear in the wrapping around an order: greetings,
  /// thanks, blessings, sign-offs. One of these is enough to call a line
  /// conversation rather than a request.
  static const _pleasantries = {
    'السلام', 'عليكم', 'ورحمه', 'وبركاته', 'صباح', 'مساء', 'الخير', 'النور',
    'شكرا', 'مشكور', 'مشكورين', 'تحياتي', 'جزاك', 'جزاكم', 'يعطيك', 'يعطيكم',
    'العافيه', 'حياك', 'اهلا', 'مرحبا', 'تسلم', 'تسلمو', 'الله', 'وعليكم',
  };

  /// A line is only dropped when it is plainly not asking for anything: it
  /// says thank you, or it contains no word that could name a product at all
  /// (a bare phone number, a stray "٣ كرتون").
  static bool _isNoise(List<String> tokens) {
    // "وشكرا" is thanks with the conjunction glued on, same as everywhere else.
    bool isPleasantry(String t) =>
        _pleasantries.contains(t) ||
        (t.length >= 4 &&
            _proclitics.contains(t[0]) &&
            _pleasantries.contains(t.substring(1)));

    if (tokens.any(isPleasantry)) return true;
    return !tokens.any(_isContentWord);
  }

  /// "المطلوب:" and "حابين نطلب التالي لو تكرمت:" introduce the list rather
  /// than being part of it. A trailing colon is the one structural marker that
  /// says so without having to guess at meaning.
  static final _headerLine = RegExp(r':\s*$');

  /// "*Order for weekly*" — a whole line WhatsApp-bolded as a section title,
  /// not a request. Deliberately more conservative than [_headerLine]: unlike
  /// a colon, a sender routinely bolds an entire REAL product line too
  /// ("*Red tea 2crt*"), and misreading that as a header silently drops an
  /// order — the one failure this design can't tolerate. See where this is
  /// used in [_matchLine]: only once the line has already matched nothing.
  static final _wrappedHeaderLine = RegExp(r'^\*.+\*$');

  RequestLine _matchLine(String text) {
    final tokens = ArabicText.tokenize(text);
    final quantity = _quantityIn(tokens);
    if (_headerLine.hasMatch(text) || _isNoise(tokens)) {
      return RequestLine(
        text: text,
        quantity: quantity,
        candidates: const [],
        isNoise: true,
      );
    }

    // Expand each line token to the catalog words it could be, once per line
    // rather than once per row — this is what keeps a 194-row scan cheap.
    final matchedVocab = <String, double>{};
    for (final token in tokens.toSet()) {
      for (final entry in _bestVocabMatches(token)) {
        final existing = matchedVocab[entry.key];
        if (existing == null || entry.value > existing) {
          matchedVocab[entry.key] = entry.value;
        }
      }
    }

    final touched = <int>{};
    for (final vocab in matchedVocab.keys) {
      touched.addAll(_postings[vocab]!);
    }

    // How much of what the line said was recognised at all. Divides by the
    // catalog-known words only, so "السلام عليكم" in front of a real order
    // doesn't drag the score down.
    final lineWeight = matchedVocab.keys.fold<double>(0, (sum, t) => sum + _idf[t]!);

    final scored = <ScoredItem>[];
    for (final index in touched) {
      final nameTokens = _nameTokens[index];
      var matched = 0.0;
      for (final token in nameTokens.toSet()) {
        final strength = matchedVocab[token];
        if (strength != null) matched += _idf[token]! * strength;
      }
      for (final token in _extraTokens[index].toSet()) {
        final strength = matchedVocab[token];
        if (strength != null) {
          matched += _idf[token]! * strength * _extraTokenWeight;
        }
      }
      if (matched <= 0) continue;

      // A row has to share an actual product word, not just a number and a
      // unit. "نسكافيه ذهبي ٢٠٠ جم" against "زعفران اسيانا - 2 جم" agrees on
      // "2" and "جم" and on nothing that names a product — a coincidence of
      // packaging, scored like a match. Sizes discriminate between rows that
      // already share a name; on their own they mean nothing.
      final sharesContent = nameTokens.any(
        (t) => matchedVocab.containsKey(t) && _isContentWord(t),
      );
      if (!sharesContent) continue;

      // Two halves, and both matter. Coverage asks "did the line account for
      // this row?" — without it, "مياه" alone would match every water row
      // perfectly. Precision asks "did this row account for the line?" —
      // without it, a one-word row beats the more specific row that the extra
      // words were pointing at.
      // Capped: a category hit on top of a complete name match would
      // otherwise push coverage past 1.
      final coverage = min(1.0, matched / _nameWeight[index]);
      final precision = min(1.0, matched / lineWeight);
      scored.add(ScoredItem(_inventory[index], 0.7 * coverage + 0.3 * precision));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return RequestLine(
      text: text,
      quantity: quantity,
      candidates: scored.take(8).toList(),
      // Checked here, after real scoring, not against `matchedVocab.isEmpty`
      // beforehand: a header can contain a bare number that happens to be an
      // exact token inside some unrelated row's name (e.g. "3days" splits to
      // "3", which is also "...مقاس 3"'s size token) — that gives matchedVocab
      // a hit, but a purely numeric token can never pass the sharesContent
      // gate above, so `scored` still ends up empty. Gating on the actual
      // outcome, not a step along the way, is what catches this.
      isNoise: scored.isEmpty &&
          (_wrappedHeaderLine.hasMatch(text) || _isNoise(tokens)),
    );
  }

  /// How things are packed and counted. These words appear inside item names
  /// ("170 مل كرتون - شد 48") *and* as the unit being ordered ("٦ كرتون"), so
  /// they collide constantly between rows that share nothing else.
  static const _packaging = {
    'كرتون', 'كرتونة', 'علبة', 'علبه', 'كيس', 'بكت', 'باكيت', 'حبة', 'حبه',
    'شد', 'شدة', 'شده', 'عبوة', 'عبوه', 'درزن', 'صندوق', 'زجاجة', 'زجاجه',
    'ظرف', 'قطعة', 'قطعه', 'خيط',
    // English packaging/count units. 'cartoon' is a literal misspelling seen
    // in real messages ("30 cartoon water") — added as its own entry, not
    // fuzzy-tolerated, since no fuzzy fallback applies to unit words.
    'carton', 'cartoon', 'ctn', 'crt',
    'bag', 'bags', 'sack', 'sacks',
    'pack', 'pk', 'packet', 'packets',
    'box', 'boxes', 'bottle', 'bottles', 'btl',
    'piece', 'pieces', 'pc', 'pcs',
  };

  /// English hedge/filler words. Must never flip `namedSomething` true in
  /// [_quantityIn] — "please 2 kg سكر" must still read as a 2kg count, not a
  /// size, just because "please" came first — but must NOT go in
  /// [_pleasantries]: a line that also carries a real (even if unmatched)
  /// product word is a request, not noise, and dropping it silently is the
  /// one failure mode this whole feature exists to avoid.
  static const _englishFillers = {
    'only', 'just', 'please', 'pls', 'plz', 'kindly', 'also',
    'the', 'a', 'an', 'for', 'of', 'to', 'and',
  };

  /// Whether a token names something, as opposed to measuring or containing it.
  /// Numbers, units and packaging are all shared by rows with nothing to do
  /// with each other, so none of them can be the only evidence for a match.
  ///
  /// Safe even for the rows that genuinely sell containers: an order for
  /// "علبة بلاستيك" still carries "بلاستيك", which is a real word about the
  /// product.
  static bool _isContentWord(String token) =>
      token.length > 1 &&
      !_numeric.hasMatch(token) &&
      !_sizeUnits.contains(token) &&
      !_packaging.contains(token) &&
      !_englishFillers.contains(token);

  /// Catalog words this line word could be, each with how sure we are.
  Iterable<MapEntry<String, double>> _bestVocabMatches(String token) sync* {
    if (_postings.containsKey(token)) {
      yield MapEntry(token, 1);
      return;
    }

    // Arabic glues its conjunctions and prepositions onto the following word,
    // so a list written "وحليب المراعي وسكر الاسرة" contains neither حليب nor
    // سكر as far as string equality is concerned. Both lines matched nothing
    // at all before this.
    //
    // Only ever accepted when what is left is a word the catalog actually
    // uses, which is what makes it safe: "وسط" and "ورق" strip to "سط" and
    // "رق", neither of which is in the catalog, so neither is stripped.
    if (token.length >= 4 && _proclitics.contains(token[0])) {
      final stripped = token.substring(1);
      if (_postings.containsKey(stripped)) {
        yield MapEntry(stripped, 1);
        return;
      }
    }

    // An English word for a concept the catalog only writes in Arabic.
    // "coffee" must reach the same rows "قهوة" already does — several,
    // ambiguously — not one row hand-picked for it. Checked before the
    // length/numeric guard below: that guard exists to protect the fuzzy
    // trigram fallback from short-string false positives, and has nothing to
    // do with an exact dictionary lookup — "tea" (length 3) must still
    // resolve. Every alias target is matched via an exact postings check,
    // never by lowering the fuzzy threshold.
    var aliasedAny = false;
    for (final vocab in EnglishAlias.arabicFor(token)) {
      if (_postings.containsKey(vocab)) {
        yield MapEntry(vocab, 1);
        aliasedAny = true;
      }
    }
    if (aliasedAny) return;

    // A number that isn't in the catalog is a quantity, not a misspelt size.
    if (_numeric.hasMatch(token) || token.length < 4) return;

    for (final vocab in _postings.keys) {
      if (_numeric.hasMatch(vocab) || vocab.length < 4) continue;
      final similarity = ArabicText.similarity(token, vocab);
      if (similarity >= 0.75) yield MapEntry(vocab, similarity);
    }
  }

  /// The count the sender asked for, or 1.
  ///
  /// Position decides this, not the number itself. "٣ كجم شيكولاتة" is three
  /// kilos of chocolate; "عصير برتقال ٢٠٠ مل" is a two-hundred millilitre
  /// juice. The digits and the unit are identical in shape — what differs is
  /// whether a product has been named yet.
  static double _quantityIn(List<String> tokens) {
    var namedSomething = false;
    for (var i = 0; i < tokens.length; i++) {
      if (!_quantityToken.hasMatch(tokens[i])) {
        namedSomething = namedSomething || _isContentWord(tokens[i]);
        continue;
      }

      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      final bool isCount;
      if (next == null) {
        // Trailing: "سحلب 5" and "زنجبيل مطحون 500 جم 3" both end in the count.
        isCount = true;
      } else if (_packaging.contains(next)) {
        // "٢٠ حبة", "٣ كرتون" — counted in boxes, so it is a count.
        isCount = true;
      } else if (_sizeUnits.contains(next)) {
        // "٣ كجم شيكولاتة" is a count; "شيكولاتة ٣ كجم" is a size. The only
        // difference is whether the product was named first.
        isCount = !namedSomething;
      } else {
        // A number sitting inside the name — "خلاص باللوز ٥ نجوم" — is part of
        // what the thing is called, not how many were wanted.
        isCount = !namedSomething;
      }

      if (isCount) {
        final parsed = double.tryParse(tokens[i].replaceAll(',', '.'));
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return 1;
  }
}
