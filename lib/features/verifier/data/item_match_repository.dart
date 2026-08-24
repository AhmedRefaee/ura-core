import '../../../core/errors/app_result.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/item_match_result.dart';

/// Matches a written request for items against the caller's own inventory,
/// returning only matches backed by real inventory rows plus anything it
/// couldn't place.
///
/// Two implementations exist for one reason: the direct one talks to Gemini
/// from the device, and the edge one goes through Supabase. See
/// `DirectItemMatchRepository` for which is wired and why the other is kept.
abstract class ItemMatchRepository {
  /// Sends a pasted written request — typically a WhatsApp message forwarded
  /// from someone at an outside entity.
  Future<AppResult<ItemMatchResult>> matchText(
    String text,
    List<InventoryItem> inventory,
  );

  /// Called as the entry screens open, before there is anything to match, to
  /// take whatever setup cost this implementation has off the critical path.
  Future<void> warmUp();
}
