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
/// On an outbound order availability is storage's call: only a row storage
/// marked ✗ ([ItemCheckStatus.rejected]) is something the rep has to source,
/// and a row not yet reviewed is neither -- nobody knows yet, so it is not
/// painted purple. [direction] is required because inbound orders keep the
/// old reading: the rep is bringing stock *in*, nothing is "for purchase".
OffStockKind? offStockKindOf(OrderItem item, OrderDirection direction) {
  if (direction == OrderDirection.outbound) {
    if (item.checkStatus != ItemCheckStatus.rejected) return null;
    // A split-off shortfall (or a converted item) keeps a link back to the
    // inventory row it came from; a genuinely new one has nothing to link to.
    if (item.isCustom && item.sourceInventoryId == null) return OffStockKind.newItem;
    return OffStockKind.outOfStock;
  }
  if (item.isCustom) {
    return item.sourceInventoryId == null
        ? OffStockKind.newItem
        : OffStockKind.outOfStock;
  }
  return null;
}

/// The kind for one item of an order still being built.
///
/// Stock is not part of it any more: the verifier never sees what is on the
/// shelf, so only a row they typed in as a new item is flagged.
OffStockKind? draftOffStockKind({
  required bool isCustom,
  required String? sourceInventoryId,
}) {
  // The verifier does not know what is in stock -- storage decides that
  // after the order is saved -- so a draft row is only ever a new item the
  // verifier typed in themselves, never "out of stock".
  if (isCustom) {
    return sourceInventoryId == null
        ? OffStockKind.newItem
        : OffStockKind.outOfStock;
  }
  return null;
}
