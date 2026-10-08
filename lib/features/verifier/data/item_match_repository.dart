import '../../../core/errors/app_result.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/item_match_result.dart';

/// Matches a written request for items against the caller's own inventory,
/// returning only matches backed by real inventory rows plus anything it
/// couldn't place.
///
/// Several implementations exist: `LocalItemMatchRepository` matches
/// on-device with no network call, `DirectItemMatchRepository` talks to
/// Gemini from the device, `EdgeItemMatchRepository` goes through Supabase,
/// and `HybridItemMatchRepository` composes local-first with a Gemini
/// fallback for whatever local couldn't place. See `injection.dart` for
/// which is currently wired.
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
