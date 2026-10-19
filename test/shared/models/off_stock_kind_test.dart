// The rule these pin down is a product rule, not a display detail: purple
// means "the rep sources this himself". On an outbound order that is decided
// by storage -- a row it marked ✗ -- and by nobody before then.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/off_stock_kind.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/models/order_item.dart';

void main() {
  OrderItem item({
    bool isCustom = false,
    String? sourceInventoryId,
    ItemCheckStatus status = ItemCheckStatus.pending,
  }) =>
      OrderItem(
        id: 'i1',
        orderId: 'o1',
        inventoryId: isCustom ? null : 'inv-1',
        quantity: 3,
        isCustom: isCustom,
        sourceInventoryId: sourceInventoryId,
        checkStatus: status,
      );

  group('outbound: storage decides', () {
    test('an item storage has not reviewed yet is not purple, whatever it is', () {
      for (final i in [item(), item(isCustom: true)]) {
        expect(offStockKindOf(i, OrderDirection.outbound), isNull);
      }
    });

    test('an item storage marked available (✓) is ordinary stock', () {
      expect(
        offStockKindOf(item(status: ItemCheckStatus.checked), OrderDirection.outbound),
        isNull,
      );
      expect(
        offStockKindOf(
          item(isCustom: true, status: ItemCheckStatus.checked),
          OrderDirection.outbound,
        ),
        isNull,
        reason: 'a new item storage hands over is not for purchase',
      );
    });

    test('a catalogue row storage marked unavailable (✗) is out of stock', () {
      expect(
        offStockKindOf(item(status: ItemCheckStatus.rejected), OrderDirection.outbound),
        OffStockKind.outOfStock,
      );
    });

    test('a new item storage marked unavailable (✗) is a new item', () {
      expect(
        offStockKindOf(
          item(isCustom: true, status: ItemCheckStatus.rejected),
          OrderDirection.outbound,
        ),
        OffStockKind.newItem,
      );
    });

    test('a split-off shortfall keeps its link to the catalogue row', () {
      expect(
        offStockKindOf(
          item(
            isCustom: true,
            sourceInventoryId: 'inv-1',
            status: ItemCheckStatus.rejected,
          ),
          OrderDirection.outbound,
        ),
        OffStockKind.outOfStock,
      );
    });
  });

  group('inbound keeps the old reading', () {
    test('a catalogue row is ordinary, however the storage check went', () {
      for (final direction in [
        OrderDirection.inboundRep,
        OrderDirection.inboundExternal,
      ]) {
        for (final status in ItemCheckStatus.values) {
          expect(
            offStockKindOf(item(status: status), direction),
            isNull,
            reason: '${direction.name} / ${status.name}',
          );
        }
      }
    });

    test('a custom item is off-stock', () {
      for (final direction in [
        OrderDirection.inboundRep,
        OrderDirection.inboundExternal,
      ]) {
        expect(offStockKindOf(item(isCustom: true), direction), OffStockKind.newItem);
        expect(
          offStockKindOf(item(isCustom: true, sourceInventoryId: 'inv-1'), direction),
          OffStockKind.outOfStock,
        );
      }
    });
  });
}
