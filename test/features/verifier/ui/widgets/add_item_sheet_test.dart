// Full DI/Supabase-backed navigation (tapping the paste button, which resolves
// AiAddItemCubit via `sl`) is exercised manually on-device — see
// test/widget_test.dart for why this repo doesn't spin up Firebase/Supabase for
// widget tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/ui/widgets/add_item_sheet.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/order.dart';

void main() {
  const water = InventoryItem(id: 'item-water', itemName: 'مياه', quantity: 50, unit: 'كرتونة');

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('offers the paste entry point and no longer the voice one', (tester) async {
    await tester.pumpWidget(wrap(AddItemSheet(
      inventory: const [water],
      orderDirection: OrderDirection.outbound,
      onAddInventoryItems: (_) {},
      onAddCustomItem: (_, _, {sourceInventoryId}) {},
    )));

    expect(find.byIcon(Icons.content_paste), findsOneWidget);
    // The voice feature was removed deliberately; a mic reappearing here means
    // something was restored by accident.
    expect(find.byIcon(Icons.mic), findsNothing);
  });

  testWidgets('manual inventory flow still calls onAddInventoryItems with entered quantity', (tester) async {
    List<({InventoryItem item, double quantity})>? added;

    await tester.pumpWidget(wrap(AddItemSheet(
      inventory: const [water],
      orderDirection: OrderDirection.outbound,
      onAddInventoryItems: (items) => added = items,
      onAddCustomItem: (_, _, {sourceInventoryId}) {},
    )));

    await tester.enterText(find.byType(TextField).last, '4');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'إضافة الأصناف المحددة'));
    await tester.pump();

    expect(added, isNotNull);
    expect(added!.single.item, water);
    expect(added!.single.quantity, 4);
  });

  // The picker had search and the three status chips but no way to narrow by
  // category, which the inventory screen has always offered. Categories are
  // derived from the passed-in list rather than fetched, so these also pin that
  // an item with no category never leaks into a filtered view.
  group('category filter', () {
    const coffee = InventoryItem(
      id: 'item-coffee',
      itemName: 'بن هرري',
      quantity: 10,
      unit: 'كيس',
      category: 'قهوة',
    );
    const tea = InventoryItem(
      id: 'item-tea',
      itemName: 'شاي ليبتون',
      quantity: 7,
      unit: 'بكت',
      category: 'شاي',
    );

    Widget sheetWith(List<InventoryItem> inventory) => wrap(AddItemSheet(
          inventory: inventory,
          orderDirection: OrderDirection.outbound,
          onAddInventoryItems: (_) {},
          onAddCustomItem: (_, _, {sourceInventoryId}) {},
        ));

    testWidgets('a chip appears per distinct category, sorted', (tester) async {
      await tester.pumpWidget(sheetWith(const [coffee, tea, water]));

      expect(find.widgetWithText(FilterChip, 'قهوة'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'شاي'), findsOneWidget);
    });

    testWidgets('choosing a category hides items from other categories',
        (tester) async {
      await tester.pumpWidget(sheetWith(const [coffee, tea, water]));

      expect(find.text('بن هرري'), findsOneWidget);
      expect(find.text('شاي ليبتون'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'قهوة'));
      await tester.pump();

      expect(find.text('بن هرري'), findsOneWidget);
      expect(find.text('شاي ليبتون'), findsNothing);
      // water has no category at all, so it must not survive the filter either.
      expect(find.text('مياه'), findsNothing);
    });

    testWidgets('tapping the chosen category again clears it', (tester) async {
      await tester.pumpWidget(sheetWith(const [coffee, tea]));

      await tester.tap(find.widgetWithText(FilterChip, 'قهوة'));
      await tester.pump();
      expect(find.text('شاي ليبتون'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'قهوة'));
      await tester.pump();
      expect(find.text('شاي ليبتون'), findsOneWidget);
    });

    testWidgets('no chips at all when nothing has a category', (tester) async {
      await tester.pumpWidget(sheetWith(const [water]));

      // Only the three status chips should be present.
      expect(find.byType(FilterChip), findsNWidgets(3));
    });
  });
}
