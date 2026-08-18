// Full DI/Supabase-backed navigation (tapping the mic button, which
// resolves AiAddItemCubit via `sl`) is exercised manually on-device per
// the verification steps in the voice-add-item plan — see test/widget_test.dart
// for why this repo doesn't spin up Firebase/Supabase for widget tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/ui/widgets/add_item_sheet.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/order.dart';

void main() {
  const water = InventoryItem(id: 'item-water', itemName: 'مياه', quantity: 50, unit: 'كرتونة');

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders both AI entry buttons without touching DI', (tester) async {
    await tester.pumpWidget(wrap(AddItemSheet(
      inventory: const [water],
      orderDirection: OrderDirection.outbound,
      onAddInventoryItems: (_) {},
      onAddCustomItem: (_, _, {sourceInventoryId}) {},
    )));

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.content_paste), findsOneWidget);
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
}
