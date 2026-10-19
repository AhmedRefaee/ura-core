import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/item_match_repository.dart';
import 'package:ura_core/features/verifier/logic/item_draft_cubit.dart';
import 'package:ura_core/features/verifier/ui/widgets/item_draft_table.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

class _NoAi implements ItemMatchRepository {
  @override
  Future<AppResult<ItemMatchResult>> matchText(String text, List<InventoryItem> inventory) async =>
      const AppSuccess(ItemMatchResult(matches: [], unmatched: []));
  @override
  Future<void> warmUp() async {}
}

void main() {
  const water = InventoryItem(id: 'water', itemName: 'مياه نوفا 330 مل', quantity: 50, unit: 'كرتون');
  // A one-row catalog makes every word equally common, so nothing would ever
  // score; the matcher needs something to tell rows apart.
  const tea = InventoryItem(id: 'tea', itemName: 'شاي ليبتون اصفر', quantity: 9, unit: 'بكت');

  Future<(ItemDraftCubit, List<List<DraftRow>>)> pump(WidgetTester tester) async {
    final cubit = ItemDraftCubit(_NoAi());
    final commits = <List<DraftRow>>[];
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlocProvider.value(
            value: cubit,
            child: ItemDraftTable(inventory: const [water, tea], onCommit: commits.add),
          ),
        ),
      ),
    ));
    return (cubit, commits);
  }

  testWidgets('fill the entry row, tap ➕, then add to the order', (tester) async {
    final (cubit, commits) = await pump(tester);

    expect(find.widgetWithText(FilledButton, 'إضافة إلى الطلب'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'إضافة إلى الطلب')).onPressed,
      isNull,
      reason: 'nothing to add yet',
    );

    await tester.enterText(find.byKey(const ValueKey('draft-entry-name')), 'شمع معطر');
    await tester.enterText(find.byKey(const ValueKey('draft-entry-unit')), 'حبة');
    await tester.enterText(find.byKey(const ValueKey('draft-entry-qty')), '20');
    await tester.tap(find.byTooltip('إضافة صف'));
    await tester.pump();
    expect(cubit.state.rows.single.name, 'شمع معطر');

    await tester.tap(find.widgetWithText(FilledButton, 'إضافة إلى الطلب'));
    await tester.pump();
    expect(commits.single.single.quantity, 20);
    expect(commits.single.single.unit, 'حبة');
    expect(cubit.state.rows, isEmpty);
  });

  testWidgets('matching shows suggestions; picking one marks the row, default is as typed',
      (tester) async {
    final (cubit, _) = await pump(tester);
    cubit.addRow(name: 'مياه نوفا', quantityText: '3');
    await tester.pump();

    await tester.tap(find.text('مطابقة مع المخزن'));
    await tester.pumpAndSettle();
    expect(cubit.state.rows.single.suggestions, contains(water));

    expect(find.widgetWithText(ChoiceChip, 'كما كتبته'), findsOneWidget);
    expect(cubit.state.rows.single.chosen, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'مياه نوفا 330 مل'));
    await tester.pump();
    expect(cubit.state.rows.single.chosen, water);
  });
}
