// Storage decides what a typed line is. The one rule worth pinning: the
// sheet only ever *suggests* a catalog row when the words are exactly ones
// seen before -- never a near-miss, which is how the old matcher went wrong.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/storage/ui/widgets/typed_line_review_sheet.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/order_item.dart';

void main() {
  const tea = InventoryItem(
    id: 'inv-tea',
    itemName: 'شاي ربيع 100 كيس',
    quantity: 12,
    unit: 'علبة',
    aliases: ['شاي ربيع'],
  );
  const sugar = InventoryItem(id: 'inv-sugar', itemName: 'سكر الأسرة', quantity: 30, unit: 'كيس');
  const inventory = [tea, sugar];

  OrderItem typed(String name, {String unit = 'علبة', double qty = 2}) => OrderItem(
        id: 'line-1',
        orderId: 'o1',
        quantity: qty,
        isCustom: true,
        customDescription: jsonEncode({'name': name, 'unit': unit, 'qty': qty}),
        checkStatus: ItemCheckStatus.pending,
      );

  group('rememberedLinks', () {
    test('an alias storage confirmed before is suggested', () {
      expect(rememberedLinks('شاي ربيع', inventory), [tea]);
    });

    test('the same name, spelled with another alef, still counts', () {
      expect(rememberedLinks('سكر الاسرة', inventory), [sugar]);
    });

    test('a near-miss is never suggested', () {
      expect(rememberedLinks('شاي', inventory), isEmpty);
      expect(rememberedLinks('شاي ربيع اخضر', inventory), isEmpty);
    });
  });

  group('the item model', () {
    test('a typed line storage linked is told apart from a template line', () {
      final linked = OrderItem(
        id: 'l',
        orderId: 'o',
        inventoryId: 'inv-tea',
        quantity: 2,
        isCustom: false,
        customDescription: jsonEncode({'name': 'شاي ربيع'}),
        checkStatus: ItemCheckStatus.checked,
      );
      const template = OrderItem(
        id: 't',
        orderId: 'o',
        inventoryId: 'inv-tea',
        quantity: 2,
        isCustom: false,
        checkStatus: ItemCheckStatus.pending,
      );
      expect(linked.isLinkedTypedLine, isTrue);
      expect(linked.typedName, 'شاي ربيع');
      expect(template.isTypedLine, isFalse);
    });
  });

  Future<TypedLineChoice?> open(WidgetTester tester, OrderItem item) async {
    TypedLineChoice? picked;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              picked = await showTypedLineReviewSheet(
                context,
                item: item,
                loadInventory: () async => inventory,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    return picked;
  }

  testWidgets('offers the three choices, plus the remembered link', (tester) async {
    await open(tester, typed('شاي ربيع'));
    expect(find.text('ربط بـ شاي ربيع 100 كيس'), findsOneWidget);
    expect(find.text('ربط بصنف في المخزن'), findsOneWidget);
    expect(find.text('إضافة كصنف جديد'), findsOneWidget);
    expect(find.text('متوفر فقط'), findsOneWidget);
  });

  testWidgets('no remembered link for words never seen', (tester) async {
    await open(tester, typed('بن هرري'));
    expect(find.textContaining('من مرة سابقة'), findsNothing);
  });

  testWidgets('same unit: tapping the remembered link links straight away', (tester) async {
    TypedLineChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showTypedLineReviewSheet(
              context,
              item: typed('شاي ربيع'),
              loadInventory: () async => inventory,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ربط بـ شاي ربيع 100 كيس'));
    await tester.pumpAndSettle();
    final link = result as LinkToCatalog;
    expect(link.item, tea);
    expect(link.quantity, isNull);
  });

  testWidgets('another unit: storage restates the quantity before linking', (tester) async {
    TypedLineChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showTypedLineReviewSheet(
              context,
              item: typed('شاي ربيع', unit: 'كرتون', qty: 2),
              loadInventory: () async => inventory,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ربط بـ شاي ربيع 100 كيس'));
    await tester.pumpAndSettle();
    expect(find.text('الكمية بوحدة المخزن'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '24');
    await tester.tap(find.text('ربط'));
    await tester.pumpAndSettle();
    expect((result as LinkToCatalog).quantity, 24);
  });
}
