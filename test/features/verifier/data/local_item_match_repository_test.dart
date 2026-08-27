// The policy layer: where a ranking becomes "added to the order", "pick one of
// these", or "nothing here, keep what you typed". Getting this wrong is the
// only way the local matcher can actually hurt someone, so the bar for adding
// a row unasked is pinned here rather than left to drift.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/local_item_match_repository.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

void main() {
  const water330 = InventoryItem(
    id: 'water-330',
    itemName: 'مياه نوفا 330 مل',
    quantity: 50,
    unit: 'كرتونة',
    category: 'مشروبات',
  );
  const water500 = InventoryItem(
    id: 'water-500',
    itemName: 'مياه نوفا 500 مل',
    quantity: 40,
    unit: 'كرتونة',
    category: 'مشروبات',
  );
  const soap = InventoryItem(
    id: 'soap-lux',
    itemName: 'صابون لوكس',
    quantity: 20,
    unit: 'علبة',
    category: 'منظفات',
  );
  const inventory = [water330, water500, soap];

  final repository = LocalItemMatchRepository();

  Future<ItemMatchResult> match(String text) async {
    final result = await repository.matchText(text, inventory);
    return (result as AppSuccess<ItemMatchResult>).data;
  }

  test('a fully specified line is added without asking', () async {
    final result = await match('3 كرتونة مياه نوفا 330 مل');

    expect(result.matches.single.itemId, 'water-330');
    expect(result.matches.single.quantity, 3);
    expect(result.ambiguous, isEmpty);
    expect(result.unmatched, isEmpty);
  });

  test('a line that fits two rows is offered as a choice, never guessed',
      () async {
    final result = await match('2 كرتونة مياه نوفا');

    expect(result.matches, isEmpty, reason: 'must not pick one silently');
    expect(result.ambiguous.single.candidateItemIds,
        containsAll(['water-330', 'water-500']));
    expect(result.ambiguous.single.quantity, 2);
    // The verifier needs to see what was written, not just the options.
    expect(result.ambiguous.single.text, contains('مياه نوفا'));
  });

  test('a line the catalog has nothing for keeps the sender\'s own words',
      () async {
    final result = await match('5 مكنسة كهربائية');

    expect(result.matches, isEmpty);
    expect(result.ambiguous, isEmpty);
    expect(result.unmatched.single.text, contains('مكنسة'));
    expect(result.unmatched.single.quantity, 5);
  });

  test('greetings and phone numbers are dropped, not reported as failures',
      () async {
    final result = await match('''
السلام عليكم ورحمة الله
معاك احمد من فرع المعادي
3 علبة صابون لوكس
وشكرا جزيلا
01001234567
''');

    expect(result.matches.single.itemId, 'soap-lux');
    expect(result.ambiguous, isEmpty);
    // The greeting, the thanks and the phone number are gone. The line naming
    // a person and a branch survives as an unmatched line, which is the safe
    // direction to be wrong in: unmatched items start unchecked, so it costs a
    // glance rather than a wrong row in the order.
    expect(result.unmatched.map((u) => u.text),
        isNot(anyElement(contains('شكرا'))));
    expect(result.unmatched.map((u) => u.text),
        isNot(anyElement(contains('01001234567'))));
  });

  test('a single surviving candidate becomes a custom item, not a question',
      () async {
    // Offering exactly one option reads as a pointless question; the sender's
    // own wording is more useful than a lone guess.
    final result = await match('صابون معطر فاخر جدا');

    expect(result.ambiguous, isEmpty);
    expect(result.matches, isEmpty);
    expect(result.unmatched, hasLength(1));
  });

  test('an empty message produces nothing at all', () async {
    final result = await match('   \n  \n');

    expect(result.matches, isEmpty);
    expect(result.ambiguous, isEmpty);
    expect(result.unmatched, isEmpty);
  });

  test('an English word offers a choice across brands, just like Arabic would',
      () async {
    const greenTeaA = InventoryItem(
      id: 'tea-a',
      itemName: 'احمد شاي اخضر',
      quantity: 30,
      unit: 'بكت',
      category: 'شاي',
    );
    const greenTeaB = InventoryItem(
      id: 'tea-b',
      itemName: 'الربيع شاي اخضر',
      quantity: 30,
      unit: 'بكت',
      category: 'شاي',
    );
    // water330/soap are unrelated filler: with only the two tea rows, both
    // sharing every discriminating word, IDF correctly zeroes them out as
    // uninformative and nothing would score at all — an artifact of the
    // fixture, not of English matching, so give it a normal-shaped catalog.
    final result = await LocalItemMatchRepository()
        .matchText('green tea', [greenTeaA, greenTeaB, water330, soap]);
    final data = (result as AppSuccess<ItemMatchResult>).data;

    expect(data.matches, isEmpty, reason: 'must not pick a brand silently');
    expect(data.ambiguous.single.candidateItemIds,
        containsAll(['tea-a', 'tea-b']));
  });

  test('an English word for a product genuinely absent from the catalog keeps the sender\'s wording',
      () async {
    final result = await match('nescafe');

    expect(result.matches, isEmpty);
    expect(result.ambiguous, isEmpty);
    expect(result.unmatched.single.text, 'nescafe');
  });

  test('several items in one message are each resolved on their own', () async {
    final result = await match('''
3 كرتونة مياه نوفا 330 مل
2 علبة صابون لوكس
4 كرتونة مياه نوفا
''');

    expect(result.matches, hasLength(2));
    expect(result.ambiguous, hasLength(1));
  });
}
