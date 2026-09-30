import 'order.dart';
import 'order_item.dart';

/// Why an item is purple.
///
/// Purple has one meaning across the whole app: **the rep has to source this
/// himself, it is not coming off a shelf.** Two different situations produce
/// that same instruction, and until this enum existed only one of them was
/// actually painted purple:
///
/// * [newItem] — the item is not an inventory row at all. Somebody asked for
///   something the business does not carry.
/// * [outOfStock] — the item *is* an inventory row, but there were none of it
///   when the order was written. To the rep this is the same job; to the
///   verifier and the storage actor it is a very different fact, which is why
///   the two are told apart on the badge instead of being merged.
///
/// Before this, the second case showed an orange "غير متوفر" warning chip
/// while the first showed the purple badge — so the colour the rep had been
/// taught to read as "buy this" covered only half the things he had to buy.
enum OffStockKind { newItem, outOfStock }

/// The kind for one item of a saved order, or null when it is ordinary stock.
///
/// [direction] is required and not optional: `wasUnavailableAtCreation` only
/// carries this meaning on an outbound order. On an inbound one the rep is
/// bringing stock *in*, so a zero on-hand count is the normal state of an item
/// he is about to deliver — reading it as "go buy this" would be backwards.
OffStockKind? offStockKindOf(OrderItem item, OrderDirection direction) {
  if (item.isCustom) {
    // A converted item keeps a link back to the row it came from; a genuinely
    // new one has nothing to link to. That link is the only thing separating
    // the two, since both are stored as is_custom.
    return item.sourceInventoryId == null
        ? OffStockKind.newItem
        : OffStockKind.outOfStock;
  }
  if (direction == OrderDirection.outbound && item.wasUnavailableAtCreation) {
    return OffStockKind.outOfStock;
  }
  return null;
}

/// The kind for one item of an order still being built.
///
/// A draft row has no `was_unavailable_at_creation` — the database sets that
/// when the order is inserted. While the verifier is still typing, the live
/// [inventoryQuantity] of the row he picked is the same fact, one moment
/// earlier, so the draft list classifies off that instead. Pass null when the
/// item is not an inventory row or the inventory has not loaded.
OffStockKind? draftOffStockKind({
  required bool isCustom,
  required String? sourceInventoryId,
  required OrderDirection direction,
  required double? inventoryQuantity,
}) {
  if (isCustom) {
    return sourceInventoryId == null
        ? OffStockKind.newItem
        : OffStockKind.outOfStock;
  }
  if (direction == OrderDirection.outbound &&
      inventoryQuantity != null &&
      inventoryQuantity <= 0) {
    return OffStockKind.outOfStock;
  }
  return null;
}
