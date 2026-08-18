import 'package:equatable/equatable.dart';

/// A spoken item phrase the backend matched to a real inventory row.
/// [itemId] is only ever an id the backend re-validated against the
/// organization's actual inventory — never an id invented by the model.
class VoiceItemMatch extends Equatable {
  final String itemId;
  final double quantity;
  final double confidence;

  const VoiceItemMatch({
    required this.itemId,
    required this.quantity,
    required this.confidence,
  });

  factory VoiceItemMatch.fromMap(Map<String, dynamic> map) {
    return VoiceItemMatch(
      itemId: map['item_id'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  List<Object?> get props => [itemId, quantity, confidence];
}

/// A spoken item phrase that could not be confidently matched to any
/// real inventory row. Carries whatever quantity/unit the model parsed
/// so it can be prefilled into the existing custom-item flow.
class VoiceUnmatchedItem extends Equatable {
  final String text;
  final double? quantity;
  final String? unit;

  const VoiceUnmatchedItem({
    required this.text,
    this.quantity,
    this.unit,
  });

  factory VoiceUnmatchedItem.fromMap(Map<String, dynamic> map) {
    return VoiceUnmatchedItem(
      text: map['text'] as String,
      quantity: (map['quantity'] as num?)?.toDouble(),
      unit: map['unit'] as String?,
    );
  }

  @override
  List<Object?> get props => [text, quantity, unit];
}

/// A spoken item phrase that names a real product/brand but is missing an
/// attribute (size, packaging, flavor, etc.) that distinguishes multiple
/// real inventory rows — e.g. "Nova water" when both a 330ml and 500ml
/// inventory row exist. [candidateItemIds] are only ever ids the backend
/// re-validated against the organization's actual inventory.
class VoiceAmbiguousItem extends Equatable {
  final String text;
  final double? quantity;
  final String? unit;
  final List<String> candidateItemIds;

  const VoiceAmbiguousItem({
    required this.text,
    this.quantity,
    this.unit,
    required this.candidateItemIds,
  });

  factory VoiceAmbiguousItem.fromMap(Map<String, dynamic> map) {
    return VoiceAmbiguousItem(
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

class VoiceMatchResult extends Equatable {
  final List<VoiceItemMatch> matches;
  final List<VoiceUnmatchedItem> unmatched;
  final List<VoiceAmbiguousItem> ambiguous;
  // Short natural-language recap of what the model understood from the
  // audio, shown in the review screen so the result isn't a black box.
  final String? heardSummary;

  const VoiceMatchResult({
    required this.matches,
    required this.unmatched,
    this.ambiguous = const [],
    this.heardSummary,
  });

  factory VoiceMatchResult.fromMap(Map<String, dynamic> map) {
    return VoiceMatchResult(
      matches: (map['matches'] as List? ?? [])
          .map((e) => VoiceItemMatch.fromMap(e as Map<String, dynamic>))
          .toList(),
      unmatched: (map['unmatched'] as List? ?? [])
          .map((e) => VoiceUnmatchedItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      ambiguous: (map['ambiguous'] as List? ?? [])
          .map((e) => VoiceAmbiguousItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      heardSummary: map['heard_summary'] as String?,
    );
  }

  @override
  List<Object?> get props => [matches, unmatched, ambiguous, heardSummary];
}
