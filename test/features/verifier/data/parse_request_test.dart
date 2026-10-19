// parseRequest turns a pasted message into the verifier's three columns
// (item / unit / quantity). A row it gets wrong is fixed by hand in the draft,
// but a row it drops is a lost item -- so dropping is reserved for lines that
// are plainly not requests.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/data/local_item_matcher.dart';

void main() {
  List<String> rows(String text) =>
      LocalItemMatcher.parseRequest(text).map((r) => r.toString()).toList();

  test('count and unit come out of the name', () {
    expect(rows('٣ كرتون مياه نوفا'), ['مياه نوفا | كرتون | 3.0']);
    expect(rows('شاي ليبتون 5 بكت'), ['شاي ليبتون | بكت | 5.0']);
  });

  test('a numbered list is not read as escalating quantities', () {
    expect(rows('1- ٥ بكت شاي\n2- سكر 2 كيس'), [
      'شاي | بكت | 5.0',
      'سكر | كيس | 2.0',
    ]);
  });

  test('no count means 1, no unit means none', () {
    expect(rows('مناديل فاخرة'), ['مناديل فاخرة | - | 1.0']);
  });

  test('a size stays part of the name', () {
    expect(rows('زنجبيل مطحون 500 جم 3'), ['زنجبيل مطحون 500 جم | - | 3.0']);
  });

  test('comma and a standalone و split items on one line', () {
    expect(rows('سكر 2 كيس، قهوة 1 علبة و ٣ كراتين مياه'), [
      'سكر | كيس | 2.0',
      'قهوة | علبة | 1.0',
      'مياه | كراتين | 3.0',
    ]);
  });

  test('greetings and list headers are dropped, requests are kept', () {
    expect(
      rows('السلام عليكم\nالمطلوب:\nمكنسة كهربائية\nوشكرا'),
      ['مكنسة كهربائية | - | 1.0'],
    );
  });
}
