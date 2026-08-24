import 'dart:math';

import '../../../core/text/arabic_text.dart';
import '../../../shared/models/inventory_item.dart';

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

  /// True when not one word of this line appears anywhere in the catalog —
  /// a greeting, a sign-off, a phone number. Nothing to match, and nothing
  /// worth showing the verifier as a failure either.
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

  final List<List<String>> _itemTokens = [];
  final List<double> _itemWeight = [];

  LocalItemMatcher(List<InventoryItem> inventory) : _inventory = inventory {
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      // The unit is deliberately excluded: "كرتونة" is how it is sold, not what
      // it is, and including it makes every row look alike.
      final tokens = ArabicText.tokenize(
        [row.itemName, row.category ?? '', row.sku ?? ''].join(' '),
      );
      _itemTokens.add(tokens);
      for (final token in tokens.toSet()) {
        _postings.putIfAbsent(token, () => <int>{}).add(i);
      }
    }

    final total = inventory.length;
    for (final entry in _postings.entries) {
      _idf[entry.key] = log((total + 1) / (entry.value.length + 1)) + 1;
    }

    for (final tokens in _itemTokens) {
      _itemWeight.add(_weigh(tokens));
    }
  }

  /// What a full match on this row is worth, so coverage can be a fraction of
  /// it. Distinct tokens only: a name that repeats a word shouldn't be harder
  /// to satisfy than one that doesn't.
  double _weigh(List<String> tokens) =>
      tokens.toSet().fold<double>(0, (sum, t) => sum + (_idf[t] ?? 0));

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

  /// A leading list marker: "1." "2)" "-" "•". Numbering is not a quantity, and
  /// reading it as one turns a numbered list into escalating order sizes.
  static final _listMarker = RegExp(r'^\s*(?:[-*•·]|\d{1,2}\s*[.)\]])\s*');

  static final _quantityToken = RegExp(r'^\d+(?:[.,]\d+)?$');

  /// Splits [message] into request lines and ranks the catalog against each.
  List<RequestLine> match(String message) {
    final lines = <RequestLine>[];
    for (final raw in message.split('\n')) {
      final text = raw.replaceFirst(_listMarker, '').trim();
      if (text.isEmpty) continue;
      lines.add(_matchLine(text));
    }
    return lines;
  }

  RequestLine _matchLine(String text) {
    final tokens = ArabicText.tokenize(text);
    final quantity = _quantityIn(tokens);

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

    if (matchedVocab.isEmpty) {
      return RequestLine(
        text: text,
        quantity: quantity,
        candidates: const [],
        isNoise: true,
      );
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
      final itemTokens = _itemTokens[index];
      var matched = 0.0;
      for (final token in itemTokens.toSet()) {
        final strength = matchedVocab[token];
        if (strength != null) matched += _idf[token]! * strength;
      }
      if (matched <= 0) continue;

      // Two halves, and both matter. Coverage asks "did the line account for
      // this row?" — without it, "مياه" alone would match every water row
      // perfectly. Precision asks "did this row account for the line?" —
      // without it, a one-word row beats the more specific row that the extra
      // words were pointing at.
      final coverage = matched / _itemWeight[index];
      final precision = matched / lineWeight;
      scored.add(ScoredItem(_inventory[index], 0.7 * coverage + 0.3 * precision));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return RequestLine(
      text: text,
      quantity: quantity,
      candidates: scored.take(8).toList(),
      isNoise: false,
    );
  }

  /// Catalog words this line word could be, each with how sure we are.
  Iterable<MapEntry<String, double>> _bestVocabMatches(String token) sync* {
    if (_postings.containsKey(token)) {
      yield MapEntry(token, 1);
      return;
    }
    // A number that isn't in the catalog is a quantity, not a misspelt size.
    if (_numeric.hasMatch(token) || token.length < 4) return;

    for (final vocab in _postings.keys) {
      if (_numeric.hasMatch(vocab) || vocab.length < 4) continue;
      final similarity = ArabicText.similarity(token, vocab);
      if (similarity >= 0.75) yield MapEntry(vocab, similarity);
    }
  }

  /// The count the sender asked for, or 1.
  static double _quantityIn(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      if (!_quantityToken.hasMatch(tokens[i])) continue;
      // A number glued to a unit of measure is part of the product's name.
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      if (next != null && _sizeUnits.contains(next)) continue;
      final parsed = double.tryParse(tokens[i].replaceAll(',', '.'));
      if (parsed != null && parsed > 0) return parsed;
    }
    return 1;
  }
}
