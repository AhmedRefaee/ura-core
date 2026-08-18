import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logic/safe_emit.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/voice_match_result.dart';
import '../data/voice_match_repository.dart';

/// A voice-matched inventory row, editable in the review step before it's
/// handed off to AddItemSheet's existing onAddInventoryItems callback.
class VoiceReviewMatch extends Equatable {
  final InventoryItem item;
  final double quantity;
  final double confidence;

  const VoiceReviewMatch({
    required this.item,
    required this.quantity,
    required this.confidence,
  });

  VoiceReviewMatch copyWith({double? quantity}) => VoiceReviewMatch(
        item: item,
        quantity: quantity ?? this.quantity,
        confidence: confidence,
      );

  @override
  List<Object?> get props => [item, quantity, confidence];
}

/// A spoken phrase with no confident inventory match, editable in the
/// review step before it's handed off to AddItemSheet's existing
/// onAddCustomItem callback (same JSON-payload convention as manual entry).
/// Defaults to excluded — voice mode should only add real inventory items
/// unless the user explicitly opts a phrase into custom-item creation.
class VoiceReviewUnmatched extends Equatable {
  final String name;
  final double quantity;
  final String unit;
  final bool includeAsCustom;

  const VoiceReviewUnmatched({
    required this.name,
    required this.quantity,
    required this.unit,
    this.includeAsCustom = false,
  });

  VoiceReviewUnmatched copyWith({
    double? quantity,
    String? unit,
    bool? includeAsCustom,
  }) =>
      VoiceReviewUnmatched(
        name: name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        includeAsCustom: includeAsCustom ?? this.includeAsCustom,
      );

  @override
  List<Object?> get props => [name, quantity, unit, includeAsCustom];
}

/// A spoken phrase that names a real product but is missing an attribute
/// (size, packaging, flavor, etc.) needed to pick one specific inventory
/// row out of several candidates — e.g. "Nova water" when both a 330ml and
/// 500ml row exist. Resolved via [VoiceAddItemCubit.resolveAmbiguous].
class VoiceReviewAmbiguous extends Equatable {
  final String text;
  final double quantity;
  final String unit;
  final List<InventoryItem> candidates;

  const VoiceReviewAmbiguous({
    required this.text,
    required this.quantity,
    required this.unit,
    required this.candidates,
  });

  @override
  List<Object?> get props => [text, quantity, unit, candidates];
}

sealed class VoiceAddItemState extends Equatable {
  const VoiceAddItemState();
  @override
  List<Object?> get props => [];
}

class VoiceAddItemIdle extends VoiceAddItemState {}

class VoiceAddItemRecording extends VoiceAddItemState {
  final int elapsedSeconds;
  const VoiceAddItemRecording({this.elapsedSeconds = 0});

  @override
  List<Object?> get props => [elapsedSeconds];
}

class VoiceAddItemMatching extends VoiceAddItemState {}

class VoiceAddItemReviewing extends VoiceAddItemState {
  final List<VoiceReviewMatch> matches;
  final List<VoiceReviewUnmatched> unmatched;
  final List<VoiceReviewAmbiguous> ambiguous;
  final String? heardSummary;

  const VoiceAddItemReviewing({
    required this.matches,
    required this.unmatched,
    this.ambiguous = const [],
    this.heardSummary,
  });

  /// False while any ambiguous item is unresolved, even if other items are
  /// ready to add — one undecided "which size?" blocks the whole confirm.
  bool get canConfirm =>
      ambiguous.isEmpty &&
      (matches.isNotEmpty || unmatched.any((u) => u.includeAsCustom));

  VoiceAddItemReviewing copyWith({
    List<VoiceReviewMatch>? matches,
    List<VoiceReviewUnmatched>? unmatched,
    List<VoiceReviewAmbiguous>? ambiguous,
  }) =>
      VoiceAddItemReviewing(
        matches: matches ?? this.matches,
        unmatched: unmatched ?? this.unmatched,
        ambiguous: ambiguous ?? this.ambiguous,
        heardSummary: heardSummary,
      );

  @override
  List<Object?> get props => [matches, unmatched, ambiguous, heardSummary];
}

class VoiceAddItemError extends VoiceAddItemState {
  final String message;
  const VoiceAddItemError(this.message);

  @override
  List<Object?> get props => [message];
}

class VoiceAddItemCubit extends Cubit<VoiceAddItemState> with SafeEmit<VoiceAddItemState> {
  final VoiceMatchRepository _repository;

  VoiceAddItemCubit(this._repository) : super(VoiceAddItemIdle());

  void startRecording() => safeEmit(const VoiceAddItemRecording());

  void updateElapsed(int seconds) => safeEmit(VoiceAddItemRecording(elapsedSeconds: seconds));

  Future<void> finishRecording(
    Uint8List audioBytes,
    String mimeType,
    List<InventoryItem> inventory,
  ) async {
    if (audioBytes.isEmpty) {
      safeEmit(const VoiceAddItemReviewing(matches: [], unmatched: []));
      return;
    }

    safeEmit(VoiceAddItemMatching());

    final result = await _repository.matchVoiceAudio(audioBytes, mimeType);
    switch (result) {
      case AppSuccess(data: final matchResult):
        safeEmit(_toReviewingState(matchResult, inventory));
      case AppFailure(error: final error):
        logger.w('VoiceAddItemCubit → matching failed: ${error.message}');
        safeEmit(VoiceAddItemError(error.message));
    }
  }

  VoiceAddItemReviewing _toReviewingState(VoiceMatchResult result, List<InventoryItem> inventory) {
    final byId = {for (final item in inventory) item.id: item};
    final matches = <VoiceReviewMatch>[];
    for (final match in result.matches) {
      final item = byId[match.itemId];
      // Defense in depth: only trust matches against inventory we actually
      // have loaded, even though the backend already validated the id.
      if (item == null || match.quantity <= 0) continue;
      matches.add(VoiceReviewMatch(item: item, quantity: match.quantity, confidence: match.confidence));
    }
    final unmatched = result.unmatched
        .map((u) => VoiceReviewUnmatched(
              name: u.text,
              quantity: (u.quantity == null || u.quantity! <= 0) ? 1 : u.quantity!,
              unit: u.unit?.trim().isNotEmpty == true ? u.unit!.trim() : 'قطعة',
            ))
        .toList();

    final ambiguous = <VoiceReviewAmbiguous>[];
    for (final entry in result.ambiguous) {
      final quantity = (entry.quantity == null || entry.quantity! <= 0) ? 1.0 : entry.quantity!;
      final unit = entry.unit?.trim().isNotEmpty == true ? entry.unit!.trim() : 'قطعة';
      // Defense in depth, same as matches above: only trust candidate ids
      // against inventory we actually have loaded.
      final candidates = entry.candidateItemIds.map((id) => byId[id]).whereType<InventoryItem>().toList();
      if (candidates.length >= 2) {
        ambiguous.add(VoiceReviewAmbiguous(text: entry.text, quantity: quantity, unit: unit, candidates: candidates));
      } else if (candidates.length == 1) {
        // Nothing left to disambiguate — it's a real match.
        matches.add(VoiceReviewMatch(item: candidates.single, quantity: quantity, confidence: 1.0));
      } else {
        // No valid candidates survived — falls back to unmatched.
        unmatched.add(VoiceReviewUnmatched(name: entry.text, quantity: quantity, unit: unit));
      }
    }

    return VoiceAddItemReviewing(
      matches: matches,
      unmatched: unmatched,
      ambiguous: ambiguous,
      heardSummary: result.heardSummary,
    );
  }

  void updateMatchQuantity(int index, double quantity) {
    final current = state;
    if (current is! VoiceAddItemReviewing) return;
    final updated = [...current.matches];
    updated[index] = updated[index].copyWith(quantity: quantity);
    safeEmit(current.copyWith(matches: updated));
  }

  void removeMatch(int index) {
    final current = state;
    if (current is! VoiceAddItemReviewing) return;
    final updated = [...current.matches]..removeAt(index);
    safeEmit(current.copyWith(matches: updated));
  }

  void updateUnmatched(int index, {double? quantity, String? unit, bool? includeAsCustom}) {
    final current = state;
    if (current is! VoiceAddItemReviewing) return;
    final updated = [...current.unmatched];
    updated[index] = updated[index].copyWith(
      quantity: quantity,
      unit: unit,
      includeAsCustom: includeAsCustom,
    );
    safeEmit(current.copyWith(unmatched: updated));
  }

  void resolveAmbiguous(int index, InventoryItem chosen) {
    final current = state;
    if (current is! VoiceAddItemReviewing) return;
    final entry = current.ambiguous[index];
    final updatedAmbiguous = [...current.ambiguous]..removeAt(index);
    final updatedMatches = [
      ...current.matches,
      VoiceReviewMatch(item: chosen, quantity: entry.quantity, confidence: 1.0),
    ];
    safeEmit(current.copyWith(matches: updatedMatches, ambiguous: updatedAmbiguous));
  }

  /// None of the offered candidates were what the user meant — drop the
  /// ambiguous choice instead of forcing one, same escape hatch an unmatched
  /// item already has (opt-in custom-item checkbox, unchecked by default).
  void dismissAmbiguous(int index) {
    final current = state;
    if (current is! VoiceAddItemReviewing) return;
    final entry = current.ambiguous[index];
    final updatedAmbiguous = [...current.ambiguous]..removeAt(index);
    final updatedUnmatched = [
      ...current.unmatched,
      VoiceReviewUnmatched(name: entry.text, quantity: entry.quantity, unit: entry.unit),
    ];
    safeEmit(current.copyWith(unmatched: updatedUnmatched, ambiguous: updatedAmbiguous));
  }

  void retry() => safeEmit(VoiceAddItemIdle());

  void reset() => safeEmit(VoiceAddItemIdle());
}
