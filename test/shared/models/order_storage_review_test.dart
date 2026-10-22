// storageReviewed / storageSendsItems / skipsStorageStep decide the whole
// outbound journey (stepper, timeline, rep screen, storage queue), so the
// three states of "has storage decided yet, and is it sending anything" are
// pinned here once.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/models/order_item.dart';

void main() {
  OrderItem item(ItemCheckStatus status) => OrderItem(
        id: status.name,
        orderId: 'o1',
        inventoryId: 'inv',
        quantity: 1,
        isCustom: false,
        checkStatus: status,
      );

  Order order(List<OrderItem> items, {bool reviewed = true}) => Order(
        id: 'o1',
        direction: OrderDirection.outbound,
        entityId: 'e1',
        status: OrderStatus.assigned,
        createdBy: 'v1',
        storageReviewedAt: reviewed ? DateTime(2026, 10, 20) : null,
        items: items,
      );

  test('before the review nothing is skipped, even with no item checked yet', () {
    final o = order([item(ItemCheckStatus.pending)], reviewed: false);
    expect(o.storageReviewed, isFalse);
    expect(o.storageSendsItems, isFalse);
    expect(o.skipsStorageStep, isFalse);
  });

  test('reviewed with at least one ✓: storage sends, step is kept', () {
    final o = order([item(ItemCheckStatus.checked), item(ItemCheckStatus.rejected)]);
    expect(o.storageSendsItems, isTrue);
    expect(o.skipsStorageStep, isFalse);
  });

  test('reviewed with every row ✗: nothing sent, the storage step is skipped', () {
    final o = order([item(ItemCheckStatus.rejected), item(ItemCheckStatus.rejected)]);
    expect(o.storageSendsItems, isFalse);
    expect(o.skipsStorageStep, isTrue);
  });
}
