import 'package:equatable/equatable.dart';

/// A requested item phrase the backend matched to a real inventory row.
/// [itemId] is only ever an id the backend re-validated against the
/// organization's actual inventory — never an id invented by the model.
class MatchedItem extends Equatable {
  final String itemId;
  final double quantity;
  final double confidence;

  const MatchedItem({
    required this.itemId,
    required this.quantity,
    required this.confidence,
  });

  factory MatchedItem.fromMap(Map<String, dynamic> map) {
    return MatchedItem(
      itemId: map['item_id'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  List<Object?> get props => [itemId, quantity, confidence];
}

/// A requested item phrase that could not be confidently matched to any
/// real inventory row. Carries whatever quantity/unit the model parsed
/// so it can be prefilled into the existing custom-item flow.
class UnmatchedItem extends Equatable {
  final String text;
  final double? quantity;
  final String? unit;

  const UnmatchedItem({
    required this.text,
    this.quantity,
    this.unit,
  });

  factory UnmatchedItem.fromMap(Map<String, dynamic> map) {
    return UnmatchedItem(
      text: map['text'] as String,
      quantity: (map['quantity'] as num?)?.toDouble(),
      unit: map['unit'] as String?,
    );
  }

  @override
  List<Object?> get props => [text, quantity, unit];
}

/// A requested item phrase that names a real product/brand but is missing an
/// attribute (size, packaging, flavor, etc.) that distinguishes multiple
/// real inventory rows — e.g. "Nova water" when both a 330ml and 500ml
/// inventory row exist. [candidateItemIds] are only ever ids the backend
/// re-validated against the organization's actual inventory.
class AmbiguousItem extends Equatable {
  final String text;
  final double? quantity;
  final String? unit;
  final List<String> candidateItemIds;

  const AmbiguousItem({
    required this.text,
    this.quantity,
    this.unit,
    required this.candidateItemIds,
  });

  factory AmbiguousItem.fromMap(Map<String, dynamic> map) {
    return AmbiguousItem(
      text: map['text'] as String,
      quantity: (map['quantity'] as num?)?.toDouble(),
      unit: map['unit'] as String?,
      candidateItemIds: (map['candidate_item_ids'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }

  @override
  List<Object?> get props => [text, quantity, unit, candidateItemIds];
}

class ItemMatchResult extends Equatable {
  final List<MatchedItem> matches;
  final List<UnmatchedItem> unmatched;
  final List<AmbiguousItem> ambiguous;
  // Short natural-language recap of what the model understood from the
  // request, shown in the review screen so the result isn't a black box.
  final String? heardSummary;

  const ItemMatchResult({
    required this.matches,
    required this.unmatched,
    this.ambiguous = const [],
    this.heardSummary,
  });

  factory ItemMatchResult.fromMap(Map<String, dynamic> map) {
    return ItemMatchResult(
      matches: (map['matches'] as List? ?? [])
          .map((e) => MatchedItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      unmatched: (map['unmatched'] as List? ?? [])
          .map((e) => UnmatchedItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      ambiguous: (map['ambiguous'] as List? ?? [])
          .map((e) => AmbiguousItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      heardSummary: map['heard_summary'] as String?,
    );
  }

  @override
  List<Object?> get props => [matches, unmatched, ambiguous, heardSummary];
}
