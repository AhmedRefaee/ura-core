import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/entity.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/widgets/entity_picker.dart';

void main() {
  const supplier = Entity(
    id: 'e-supplier',
    name: 'مورد المياه',
    category: EntityCategory.incoming,
  );
  const client = Entity(
    id: 'e-client',
    name: 'عميل الفندق',
    category: EntityCategory.outgoing,
  );

  Future<void> openSheet(WidgetTester tester, EntityCategory? initial) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntityPicker(
          entities: const [supplier, client],
          selected: null,
          initialCategory: initial,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byType(EntityPicker));
    await tester.pumpAndSettle();
  }

  testWidgets('outbound default shows only توريد entities', (tester) async {
    await openSheet(tester, OrderDirection.outbound.defaultEntityCategory);

    expect(find.text(client.name), findsOneWidget);
    expect(find.text(supplier.name), findsNothing);
  });

  testWidgets('inbound default shows only مشتريات entities', (tester) async {
    await openSheet(tester, OrderDirection.inboundRep.defaultEntityCategory);

    expect(find.text(supplier.name), findsOneWidget);
    expect(find.text(client.name), findsNothing);
  });

  testWidgets('the default is only a starting point — الكل shows everything',
      (tester) async {
    await openSheet(tester, OrderDirection.outbound.defaultEntityCategory);

    await tester.tap(find.widgetWithText(FilterChip, 'الكل'));
    await tester.pumpAndSettle();

    expect(find.text(client.name), findsOneWidget);
    expect(find.text(supplier.name), findsOneWidget);
  });

  testWidgets('no initialCategory keeps the old unfiltered behaviour',
      (tester) async {
    await openSheet(tester, null);

    expect(find.text(client.name), findsOneWidget);
    expect(find.text(supplier.name), findsOneWidget);
  });
}
