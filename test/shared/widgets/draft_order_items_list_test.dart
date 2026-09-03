// The one screen that had no visual distinction between a real inventory row
// and an outside-inventory one at all — everything else in the app at least
// had a different icon colour. These pin the grouping and, most importantly,
// that onRemove still points at the right index once the two groups are
// rendered apart from each other rather than in original order.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/draft_order_item.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/widgets/draft_order_items_list.dart';
import 'package:ura_core/shared/widgets/off_stock.dart';

void main() {
  const water = InventoryItem(
    id: 'water',
    itemName: 'مياه نوفا 330 مل',
    quantity: 50,
    unit: 'كرتونة',
  );

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('a stock item and an outside-inventory item are both shown',
      (tester) async {
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
        DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
      ],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (_) {},
    )));

    expect(find.text('مياه نوفا 330 مل'), findsOneWidget);
    expect(find.text('شاي ليبتون'), findsOneWidget);
  });

  testWidgets('the outside-inventory item is set apart with its own label',
      (tester) async {
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
      ],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (_) {},
    )));

    expect(find.textContaining(OffStock.label), findsWidgets);
  });

  testWidgets('a stock item shows no outside-inventory label', (tester) async {
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
      ],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (_) {},
    )));

    expect(find.textContaining(OffStock.label), findsNothing);
  });

  testWidgets(
      'removing an outside-inventory row removes the right item, not the '
      'one that happens to render at the same visual position', (tester) async {
    int? removedIndex;
    // Index 0 is stock, index 1 is outside-inventory. The outside-inventory
    // section renders second on screen despite being second in the list too
    // here — the risky case is when a later section item is tapped after the
    // groups have been split apart from their original order.
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
        DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
      ],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (i) => removedIndex = i,
    )));

    await tester.tap(find.byIcon(Icons.delete_outline).last);

    expect(removedIndex, 1);
  });

  testWidgets(
      'a stock row tapped for removal is unaffected by an outside-inventory '
      'row rendered after it', (tester) async {
    int? removedIndex;
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
        DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
      ],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (i) => removedIndex = i,
    )));

    await tester.tap(find.byIcon(Icons.delete_outline).first);

    expect(removedIndex, 0);
  });

  testWidgets(
      'an outside-inventory row placed before a stock row in the original '
      'list still removes by its real index', (tester) async {
    int? removedIndex;
    // The dangerous ordering: outside-inventory is index 0 here, but the
    // section always renders stock first, so this item is visually second.
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
        DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
      ],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (i) => removedIndex = i,
    )));

    // Visually first is the stock row (index 1); visually last is the
    // outside-inventory row (index 0).
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    expect(removedIndex, 0);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    expect(removedIndex, 1);
  });

  testWidgets('an all-outside-inventory list needs no stock section at all',
      (tester) async {
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [
        DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
      ],
      inventory: const [],
      direction: OrderDirection.outbound,
      onRemove: (_) {},
    )));

    expect(find.text('شاي ليبتون'), findsOneWidget);
  });

  testWidgets('an empty list still shows the empty-state message', (tester) async {
    await tester.pumpWidget(wrap(DraftOrderItemsList(
      items: const [],
      inventory: const [water],
      direction: OrderDirection.outbound,
      onRemove: (_) {},
    )));

    expect(find.text('لم يتم إضافة أصناف بعد'), findsOneWidget);
  });

  group('editing an outside-inventory item', () {
    testWidgets('only an outside-inventory row offers editing', (tester) async {
      await tester.pumpWidget(wrap(DraftOrderItemsList(
        items: const [
          DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
          DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
        ],
        inventory: const [water],
        direction: OrderDirection.outbound,
        onRemove: (_) {},
        onEditCustom: (_) {},
      )));

      // Two rows, but a stock row has nothing custom to edit.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('no edit affordance appears when the screen provides no handler',
        (tester) async {
      // The template editor reuses this list and has no edit flow. Offering a
      // dead button there would be worse than offering nothing.
      await tester.pumpWidget(wrap(DraftOrderItemsList(
        items: const [
          DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
        ],
        inventory: const [],
        direction: OrderDirection.outbound,
        onRemove: (_) {},
      )));

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets(
        'editing reports the real index even when the row renders far from '
        'its position in the list', (tester) async {
      // Same trap the removal tests guard: outside-inventory rows are pulled
      // into their own section, so screen order is not list order.
      int? editedIndex;
      await tester.pumpWidget(wrap(DraftOrderItemsList(
        items: const [
          DraftOrderItem(customDescription: 'شاي ليبتون', quantity: 2, isCustom: true),
          DraftOrderItem(inventoryId: 'water', inventoryName: 'مياه نوفا 330 مل', quantity: 3, isCustom: false),
          DraftOrderItem(customDescription: 'سكر', quantity: 1, isCustom: true),
        ],
        inventory: const [water],
        direction: OrderDirection.outbound,
        onRemove: (_) {},
        onEditCustom: (i) => editedIndex = i,
      )));

      // The stock row renders first, so both edit icons belong to items 0 and
      // 2 of the original list, in that order.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      expect(editedIndex, 0);

      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      expect(editedIndex, 2);
    });
  });
}
