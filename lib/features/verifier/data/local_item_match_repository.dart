import '../../../core/errors/app_result.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/item_match_result.dart';
import '../../../core/logging/app_logger.dart';
import 'item_match_repository.dart';
import 'local_item_matcher.dart';

/// Matches a pasted request against the inventory on the device, with no
/// network call at all.
///
/// This is the same [ItemMatchRepository] the Gemini implementations satisfy,
/// so the cubit, the review screen and the custom-item flow are untouched — the
/// swap is one line in `injection.dart`.
///
/// It answers in about a millisecond, works offline, costs nothing and cannot
/// run out of quota. It is also wrong more often than a good model would be,
/// and that is an acceptable trade only because of where it sits: every match
/// lands in the review step, in front of a verifier, before any of it becomes
/// an order. A wrong row here costs one tap. It never costs a delivery.
class LocalItemMatchRepository implements ItemMatchRepository {
  /// Add a row to the order without asking only above this, and only when it
  /// also clears [_autoAcceptMargin].
  ///
  /// Set deliberately high. Adding the wrong item silently is the one failure
  /// that actually hurts here; making the verifier tap an extra choice is a
  /// cost measured in seconds. Loosen this once corrections in real use say
  /// it is safe to, not before.
  static const _autoAcceptScore = 0.65;

  /// And it has to be a clear win. Several rows can fit a request equally well
  /// — "شاي اخضر" fits three — and the leader is then decided by which name
  /// happens to be shortest, which is a fact about the catalog rather than
  /// about what the sender meant.
  static const _autoAcceptMargin = 0.20;

  /// Below this a row is not worth offering. The line becomes a custom item
  /// with whatever the sender actually wrote as its name.
  static const _offerAsChoiceAbove = 0.25;

  static const _maxCandidates = 4;

  @override
  Future<AppResult<ItemMatchResult>> matchText(
    String text,
    List<InventoryItem> inventory,
  ) async {
    final started = DateTime.now();
    final lines = LocalItemMatcher(inventory).match(text);

    final matches = <MatchedItem>[];
    final ambiguous = <AmbiguousItem>[];
    final unmatched = <UnmatchedItem>[];

    for (final line in lines) {
      // A greeting or a phone number is not a failed match, and listing it as
      // one would bury the real items in things to dismiss.
      if (line.isNoise) continue;

      final best = line.best;
      if (best == null || best.score < _offerAsChoiceAbove) {
        unmatched.add(UnmatchedItem(text: line.text, quantity: line.quantity));
        continue;
      }

      final runnerUp =
          line.candidates.length > 1 ? line.candidates[1].score : 0.0;
      if (best.score >= _autoAcceptScore &&
          best.score - runnerUp >= _autoAcceptMargin) {
        matches.add(MatchedItem(
          itemId: best.item.id,
          quantity: line.quantity,
          confidence: best.score,
        ));
        continue;
      }

      final candidates = line.candidates
          .where((c) => c.score >= _offerAsChoiceAbove)
          .take(_maxCandidates)
          .map((c) => c.item.id)
          .toList();

      // One survivor is not a choice. Offering a single option reads as a
      // pointless question, so it goes to the custom-item flow instead, where
      // the verifier can see what was actually written.
      if (candidates.length >= 2) {
        ambiguous.add(AmbiguousItem(
          text: line.text,
          quantity: line.quantity,
          candidateItemIds: candidates,
        ));
      } else {
        unmatched.add(UnmatchedItem(text: line.text, quantity: line.quantity));
      }
    }

    logger.i(
      'LocalItemMatchRepository → ${matches.length} matches, '
      '${ambiguous.length} choices, ${unmatched.length} unmatched '
      'from ${lines.length} lines '
      'in ${DateTime.now().difference(started).inMilliseconds}ms',
    );

    return AppSuccess(ItemMatchResult(
      matches: matches,
      unmatched: unmatched,
      ambiguous: ambiguous,
    ));
  }

  /// Nothing to warm: there is no service in front of this.
  @override
  Future<void> warmUp() async {}
}
