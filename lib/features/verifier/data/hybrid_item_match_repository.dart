import '../../../core/errors/app_result.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/item_match_result.dart';
import 'direct_item_match_repository.dart';
import 'item_match_repository.dart';
import 'local_item_match_repository.dart';

/// Runs the local matcher first -- fast, free, right most of the time -- and
/// only calls Gemini for the lines it couldn't confidently place. One extra
/// call per paste at most, never one per line, and never at all when local
/// resolved everything.
///
/// Local's own `AmbiguousItem.candidateItemIds` is deliberately discarded for
/// lines that go to AI -- the model re-derives ambiguity from scratch against
/// the full catalog rather than being hinted with local's partial narrowing.
/// Simpler, and the model's independent judgment may do better anyway.
class HybridItemMatchRepository implements ItemMatchRepository {
  final ItemMatchRepository _local;
  final ItemMatchRepository _ai;

  HybridItemMatchRepository({ItemMatchRepository? local, ItemMatchRepository? ai})
      : _local = local ?? LocalItemMatchRepository(),
        _ai = ai ?? DirectItemMatchRepository();

  @override
  Future<AppResult<ItemMatchResult>> matchText(
    String text,
    List<InventoryItem> inventory,
  ) async {
    final localResult = await _local.matchText(text, inventory);
    if (localResult is! AppSuccess<ItemMatchResult>) return localResult;
    final local = localResult.data;

    final failedTexts = [
      for (final u in local.unmatched) u.text,
      for (final a in local.ambiguous) a.text,
    ];
    if (failedTexts.isEmpty) return localResult; // the common case: zero AI calls

    final aiResult = await _ai.matchText(failedTexts.join('\n'), inventory);
    return switch (aiResult) {
      AppSuccess(data: final ai) => AppSuccess(ItemMatchResult(
          matches: [...local.matches, ...ai.matches],
          unmatched: ai.unmatched,
          ambiguous: ai.ambiguous,
          understoodSummary: ai.understoodSummary,
        )),
      // Graceful degrade, confirmed with the user: never worse than today,
      // just misses the AI bonus this once. Logged inside _ai.matchText
      // already (both implementations log their own failures).
      AppFailure() => localResult,
    };
  }

  /// Nothing to warm on the AI side until we know what to send it -- both
  /// underlying warmUp()s are no-ops today anyway (see each class's own doc).
  @override
  Future<void> warmUp() => _local.warmUp();
}
