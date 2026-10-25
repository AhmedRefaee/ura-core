import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/ui/widgets/order_items_table.dart';
import 'package:ura_core/shared/models/draft_order_item.dart';

/// Holds the list the way create order's cubit does, so the table is
/// exercised against real round trips rather than a frozen list.
class _Host extends StatefulWidget {
  final List<DraftOrderItem> initial;
  final List<Widget> extraActions;
  const _Host({this.initial = const [], this.extraActions = const []});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final items = [...widget.initial];

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrderItemsTable(
              items: items,
              extraActions: widget.extraActions,
              onAddTyped: (lines) => setState(() => items.addAll([
                    for (final l in lines)
                      DraftOrderItem.typed(name: l.name, unit: l.unit, quantity: l.quantity),
                  ])),
              onEditTyped: (i, {name, unit, quantity}) => setState(
                  () => items[i] = items[i].withTyped(name: name, unit: unit, quantity: quantity)),
              onQuantityChanged: (i, q) => setState(() => items[i] = items[i].withQuantity(q)),
              onRemove: (i) => setState(() => items.removeAt(i)),
            ),
          ),
        ),
      );
}

void main() {
  Future<void> pumpAt(WidgetTester tester, Widget w, {double width = 800}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
  }

  List<DraftOrderItem> itemsOf(WidgetTester tester) =>
      tester.state<_HostState>(find.byType(_Host)).items;

  testWidgets('there is nothing to match: no catalog button at all', (tester) async {
    await pumpAt(tester, const _Host());
    expect(find.text('مطابقة مع المخزن'), findsNothing);
    expect(find.text('إضافة صنف'), findsOneWidget);
    expect(find.text('لصق قائمة'), findsOneWidget);
  });

  testWidgets('إضافة صنف adds a row straight into the order and focuses it', (tester) async {
    await pumpAt(tester, const _Host());
    await tester.tap(find.text('إضافة صنف'));
    await tester.pump();

    expect(itemsOf(tester), hasLength(1));
    await tester.enterText(find.byType(TextField).first, 'شاي ربيع');
    await tester.pump();
    expect(itemsOf(tester).single.typedName, 'شاي ربيع');
    expect(itemsOf(tester).single.isComplete, isTrue);
  });

  testWidgets('an unnamed row is flagged so it cannot be sent by mistake', (tester) async {
    await pumpAt(tester, _Host(initial: [DraftOrderItem.typed(name: '', quantity: 1)]));
    expect(find.text('صنف واحد ينقصه الاسم أو الكمية'), findsOneWidget);
  });

  testWidgets('pasting a list adds one row per item', (tester) async {
    await pumpAt(tester, const _Host());
    await tester.tap(find.text('لصق قائمة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'السلام عليكم\n1- سكر 2 كيس\n2- شاي');
    await tester.tap(find.text('إضافة الأصناف'));
    await tester.pumpAndSettle();

    final names = itemsOf(tester).map((i) => i.typedName).toList();
    expect(names, ['سكر', 'شاي']);
    expect(itemsOf(tester).first.quantity, 2);
  });

  testWidgets('deleting a row keeps every other row\'s own text', (tester) async {
    await pumpAt(tester, _Host(initial: [
      DraftOrderItem.typed(name: 'أول', quantity: 1),
      DraftOrderItem.typed(name: 'ثاني', quantity: 1),
    ]));
    await tester.tap(find.byTooltip('حذف').first);
    await tester.pump();
    expect(itemsOf(tester).single.typedName, 'ثاني');
    expect(find.widgetWithText(TextField, 'ثاني'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'أول'), findsNothing);
  });

  testWidgets('a catalog row (template) shows its name read-only', (tester) async {
    await pumpAt(tester, const _Host(initial: [
      DraftOrderItem(inventoryId: 'inv', inventoryName: 'سكر الأسرة', quantity: 3, isCustom: false),
    ]));
    expect(find.text('سكر الأسرة'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'سكر الأسرة'), findsNothing);
  });

  testWidgets('on a narrow phone the name gets its own line', (tester) async {
    await pumpAt(tester, _Host(initial: [DraftOrderItem.typed(name: 'شاي', quantity: 1)]), width: 360);
    final name = tester.getRect(find.widgetWithText(TextField, 'شاي'));
    final qty = tester.getRect(find.widgetWithText(TextField, '1').first);
    expect(qty.top, greaterThan(name.bottom - 1));
    expect(name.width, greaterThan(250));
    expect(find.text('الصنف'), findsNothing); // no column header when stacked
  });

  testWidgets('extra actions (the restock picker) sit beside the buttons', (tester) async {
    await pumpAt(tester, _Host(extraActions: [TextButton(onPressed: () {}, child: const Text('اختيار من المخزن'))]));
    expect(find.text('اختيار من المخزن'), findsOneWidget);
  });
}
