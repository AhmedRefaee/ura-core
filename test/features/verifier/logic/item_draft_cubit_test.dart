// The draft the verifier writes an order's items in. What matters most:
// matching only ever SUGGESTS (it is often wrong), the AI is asked only about
// rows the on-device matcher could not place, and incomplete rows are never
// silently dropped when the draft is added to the order.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/features/verifier/data/item_match_repository.dart';
import 'package:ura_core/features/verifier/logic/item_draft_cubit.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

class _FakeAi implements ItemMatchRepository {
  final List<String> asked = [];
  AppResult<ItemMatchResult> Function(String text) answer;
  _FakeAi(this.answer);

  @override
  Future<AppResult<ItemMatchResult>> matchText(String text, List<InventoryItem> inventory) async {
    asked.add(text);
    return answer(text);
  }

  @override
  Future<void> warmUp() async {}
}

void main() {
  const water = InventoryItem(id: 'water', itemName: 'مياه نوفا 330 مل', quantity: 50, unit: 'كرتون');
  const tea = InventoryItem(id: 'tea', itemName: 'شاي ليبتون اصفر 100 خيط', quantity: 9, unit: 'بكت');
  const inventory = [water, tea];

  AppResult<ItemMatchResult> none(String _) =>
      const AppSuccess(ItemMatchResult(matches: [], unmatched: []));

  test('rows are added, edited and removed', () {
    final cubit = ItemDraftCubit(_FakeAi(none));
    cubit.addRow(name: 'مياه', unit: 'كرتون', quantityText: '3');
    cubit.addRow(name: 'سكر');
    final id = cubit.state.rows.last.id;
    cubit.updateRow(id, quantityText: '2');
    expect(cubit.state.rows.last.quantity, 2);
    cubit.removeRow(cubit.state.rows.first.id);
    expect(cubit.state.rows.map((r) => r.name), ['سكر']);
  });

  test('a paste fills the draft with one row per item', () {
    final cubit = ItemDraftCubit(_FakeAi(none));
    final added = cubit.appendPasted('السلام عليكم\n1- ٣ كرتون مياه نوفا\n2- شاي 5 بكت');
    expect(added, 2);
    expect(
      cubit.state.rows.map((r) => '${r.name}|${r.unit}|${r.quantityText}'),
      ['مياه نوفا|كرتون|3', 'شاي|بكت|5'],
    );
  });

  test('matching suggests catalog rows but never picks one', () async {
    final ai = _FakeAi(none);
    final cubit = ItemDraftCubit(ai)..addRow(name: 'مياه نوفا', quantityText: '3');
    await cubit.checkMatches(inventory);
    final row = cubit.state.rows.single;
    expect(row.suggestions, contains(water));
    expect(row.chosen, isNull);
    expect(ai.asked, isEmpty, reason: 'local found it, no AI call');
  });

  test('only rows the local matcher could not place go to the AI, one call each', () async {
    final ai = _FakeAi((text) => text == 'قوارير زرق'
        ? const AppSuccess(ItemMatchResult(
            matches: [MatchedItem(itemId: 'water', quantity: 1, confidence: 0.9)],
            unmatched: [],
          ))
        : none(text));
    final cubit = ItemDraftCubit(ai)
      ..addRow(name: 'شاي ليبتون', quantityText: '1')
      ..addRow(name: 'قوارير زرق', quantityText: '2')
      ..addRow(name: 'مكنسة كهربائية', quantityText: '1');
    await cubit.checkMatches(inventory);

    expect(ai.asked, unorderedEquals(['قوارير زرق', 'مكنسة كهربائية']));
    final rows = cubit.state.rows;
    expect(rows[0].suggestions, contains(tea));
    expect(rows[1].suggestions, [water]);
    expect(rows[2].suggestions, isEmpty);
    expect(rows.every((r) => r.chosen == null), isTrue);
  });

  test('an AI failure keeps the local results and says so', () async {
    final cubit = ItemDraftCubit(_FakeAi((_) => const AppFailure(AppError(message: 'down', type: AppErrorType.server))))
      ..addRow(name: 'شاي ليبتون', quantityText: '1')
      ..addRow(name: 'شيء غريب', quantityText: '1');
    await cubit.checkMatches(inventory);
    expect(cubit.state.rows.first.suggestions, contains(tea));
    expect(cubit.state.notice, isNotNull);
    expect(cubit.state.matching, isFalse);
  });

  test('editing a name clears its now-stale suggestions and choice', () async {
    final cubit = ItemDraftCubit(_FakeAi(none))..addRow(name: 'مياه نوفا', quantityText: '1');
    await cubit.checkMatches(inventory);
    final id = cubit.state.rows.single.id;
    cubit.choose(id, water);
    cubit.updateRow(id, name: 'سكر');
    expect(cubit.state.rows.single.suggestions, isEmpty);
    expect(cubit.state.rows.single.chosen, isNull);
  });

  test('adding to the order takes complete rows and leaves incomplete ones to fix', () {
    final cubit = ItemDraftCubit(_FakeAi(none))
      ..addRow(name: 'مياه', quantityText: '3')
      ..addRow(name: '', quantityText: '2')
      ..addRow(name: 'سكر', quantityText: '0');
    final taken = cubit.takeValidRows();
    expect(taken.map((r) => r.name), ['مياه']);
    expect(cubit.state.rows, hasLength(2));
  });
}
