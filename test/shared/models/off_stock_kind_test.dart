// The rule these pin down is a product rule, not a display detail: purple
// means "the rep sources this himself". Getting the classification wrong in
// either direction is expensive -- a missed purple sends the rep to a customer
// without an item, and a spurious one sends him shopping for something that
// was on the shelf all along.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/off_stock_kind.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/models/order_item.dart';

void main() {
  OrderItem item({
    bool isCustom = false,
    String? sourceInventoryId,
    bool wasUnavailable = false,
  }) =>
      OrderItem(
        id: 'i1',
        orderId: 'o1',
        inventoryId: isCustom ? null : 'inv-1',
        quantity: 3,
        isCustom: isCustom,
        sourceInventoryId: sourceInventoryId,
        checkStatus: ItemCheckStatus.pending,
        wasUnavailableAtCreation: wasUnavailable,
      );

  group('saved order items', () {
    test('an ordinary in-stock inventory row is not off-stock', () {
      expect(
        offStockKindOf(item(), OrderDirection.outbound),
        isNull,
      );
    });

    test('a custom item with no source link is a new item', () {
      expect(
        offStockKindOf(item(isCustom: true), OrderDirection.outbound),
        OffStockKind.newItem,
      );
    });

    test('a custom item converted from a catalogue row reads as out of stock',
        () {
      // The verifier took an inventory row and turned it into free text so he
      // could describe what to buy. It is a catalogue item at heart, so
      // calling it "new" would misinform the storage actor reading the order.
      expect(
        offStockKindOf(
          item(isCustom: true, sourceInventoryId: 'inv-1'),
          OrderDirection.outbound,
        ),
        OffStockKind.outOfStock,
      );
    });

    test('an inventory row that had a zero balance is out of stock', () {
      // The case this whole change exists for: previously an orange warning
      // with no checkbox behind it.
      expect(
        offStockKindOf(item(wasUnavailable: true), OrderDirection.outbound),
        OffStockKind.outOfStock,
      );
    });
  });

  group('direction', () {
    test('a zero balance means nothing on an inbound order', () {
      // The rep is bringing this stock IN. Zero on hand is the normal state of
      // something about to be delivered, not an instruction to go buy it.
      for (final direction in [
        OrderDirection.inboundRep,
        OrderDirection.inboundExternal,
      ]) {
        expect(
          offStockKindOf(item(wasUnavailable: true), direction),
          isNull,
          reason: direction.name,
        );
      }
    });

    test('a custom item is off-stock in every direction', () {
      // Not a stock fact -- there is no row to have a balance -- so direction
      // cannot change it.
      for (final direction in OrderDirection.values) {
        expect(
          offStockKindOf(item(isCustom: true), direction),
          OffStockKind.newItem,
          reason: direction.name,
        );
      }
    });
  });

  group('draft items, classified off live stock', () {
    OffStockKind? draft({
      bool isCustom = false,
      String? sourceInventoryId,
      double? quantity,
      OrderDirection direction = OrderDirection.outbound,
    }) =>
        draftOffStockKind(
          isCustom: isCustom,
          sourceInventoryId: sourceInventoryId,
          direction: direction,
          inventoryQuantity: quantity,
        );

    test('a row with stock on hand is ordinary', () {
      expect(draft(quantity: 12), isNull);
    });

    test('a row at zero is out of stock', () {
      expect(draft(quantity: 0), OffStockKind.outOfStock);
    });

    test('a negative balance counts as zero, not as stock', () {
      // Quantities are numeric and clamped on the way out, but a bad import or
      // a manual correction can leave one below zero. Reading that as "in
      // stock" would be the worst possible answer.
      expect(draft(quantity: -4), OffStockKind.outOfStock);
    });

    test('unknown stock is left alone rather than guessed', () {
      // Inventory not loaded, or the item is not a catalogue row. Painting it
      // purple on no evidence would send the rep shopping for nothing.
      expect(draft(quantity: null), isNull);
    });

    test('a zero balance is ignored on an inbound order', () {
      expect(
        draft(quantity: 0, direction: OrderDirection.inboundRep),
        isNull,
      );
    });

    test('custom drafts split the same way saved ones do', () {
      expect(draft(isCustom: true), OffStockKind.newItem);
      expect(
        draft(isCustom: true, sourceInventoryId: 'inv-1'),
        OffStockKind.outOfStock,
      );
    });
  });
}
