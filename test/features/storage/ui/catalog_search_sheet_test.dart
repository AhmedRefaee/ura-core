// Storage swaps a picked line to another catalog row. Pinned: the same unit
// keeps the line's quantity without asking; a different unit asks first,
// because "2 كرتون" is not 2 حبة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/storage/ui/widgets/catalog_search_sheet.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/order_item.dart';

void main() {
  const water330 = InventoryItem(id: 'inv-330', itemName: 'مياه نوفا 330', quantity: 40, unit: 'كرتون');
  const water600 = InventoryItem(id: 'inv-600', itemName: 'مياه نوفا 600', quantity: 25, unit: 'كرتون');
  const waterBottle = InventoryItem(id: 'inv-bottle', itemName: 'مياه نوفا حبة', quantity: 300, unit: 'حبة');

  const picked = OrderItem(
    id: 'line-1',
    orderId: 'o1',
    inventoryId: 'inv-330',
    inventoryName: 'مياه نوفا 330',
    inventoryUnit: 'كرتون',
    quantity: 2,
    isCustom: false,
    checkStatus: ItemCheckStatus.checked,
  );

  Future<List<CatalogSwap?>> openSheet(WidgetTester tester) async {
    final results = <CatalogSwap?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await showCatalogSwapSheet(
              context,
              item: picked,
              loadInventory: () async => const [water330, water600, waterBottle],
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('same unit: swaps and keeps the quantity', (tester) async {
    final results = await openSheet(tester);
    await tester.tap(find.text('مياه نوفا 600'));
    await tester.pumpAndSettle();

    expect(results.single!.item, water600);
    expect(results.single!.quantity, isNull);
  });

  testWidgets('another unit: asks how many, then swaps with that number', (tester) async {
    final results = await openSheet(tester);
    await tester.tap(find.text('مياه نوفا حبة'));
    await tester.pumpAndSettle();

    expect(find.text('الكمية بوحدة المخزن'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '48');
    await tester.tap(find.widgetWithText(FilledButton, 'ربط'));
    await tester.pumpAndSettle();

    expect(results.single!.item, waterBottle);
    expect(results.single!.quantity, 48);
  });

  testWidgets('search narrows the list', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), '600');
    await tester.pump();

    expect(find.text('مياه نوفا 600'), findsOneWidget);
    expect(find.text('مياه نوفا حبة'), findsNothing);
  });

  test('the order line carries the app stock count when selected', () {
    final item = OrderItem.fromMap({
      'id': 'l',
      'order_id': 'o',
      'inventory_id': 'inv-330',
      'quantity': 2,
      'is_custom': false,
      'check_status': 'checked',
      'inventory': {'id': 'inv-330', 'item_name': 'مياه نوفا 330', 'unit': 'كرتون', 'quantity': 7},
    });
    expect(item.inventoryStock, 7);
  });
}
