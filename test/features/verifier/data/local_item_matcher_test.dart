// The matcher is the whole point of the local path: if it can rank a real
// WhatsApp line against the catalog on-device, most requests never need a
// model at all. These tests use a catalog shaped like the real one — several
// near-identical waters, a brand collision, a couple of unrelated rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/data/local_item_matcher.dart';
import 'package:ura_core/shared/models/inventory_item.dart';

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
  const waterOther = InventoryItem(
    id: 'water-aquafina',
    itemName: 'مياه اكوافينا 500 مل',
    quantity: 30,
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
  const soapPlain = InventoryItem(
    id: 'soap-plain',
    itemName: 'صابون سائل',
    quantity: 15,
    unit: 'علبة',
    category: 'منظفات',
  );
  const chocolate = InventoryItem(
    id: 'choc',
    itemName: 'شوكولاته جالاكسي',
    quantity: 60,
    unit: 'باكيت',
    category: 'حلويات',
  );

  final inventory = [water330, water500, waterOther, soap, soapPlain, chocolate];
  final matcher = LocalItemMatcher(inventory);

  RequestLine only(String message) {
    final lines = matcher.match(message).where((l) => !l.isNoise).toList();
    expect(lines, hasLength(1), reason: 'expected exactly one real line');
    return lines.single;
  }

  group('ranking', () {
    test('a fully specified name wins outright', () {
      final line = only('مياه نوفا 330 مل');

      expect(line.best!.item, water330);
      expect(line.best!.score, greaterThan(line.candidates[1].score));
    });

    test('the size is what separates two otherwise identical rows', () {
      expect(only('مياه نوفا 500').best!.item, water500);
      expect(only('مياه نوفا 330').best!.item, water330);
    });

    test('the brand is what separates two rows of the same size', () {
      expect(only('اكوافينا 500').best!.item, waterOther);
    });

    test('a bare category word ranks its rows without picking one confidently',
        () {
      final line = only('مياه');

      // Every water row is a legitimate reading, so no single one should look
      // settled — this is exactly the case that must reach the verifier.
      expect(line.candidates.length, greaterThanOrEqualTo(3));
      expect(line.best!.score, lessThan(0.7));
    });

    test('a more specific row beats the shorter one the extra words point at',
        () {
      expect(only('صابون لوكس').best!.item, soap);
      expect(only('صابون سائل').best!.item, soapPlain);
    });

    test('a typo still finds the row', () {
      // شيكولاته for شوكولاته — the vowel people disagree about.
      expect(only('شيكولاته جالاكسي').best!.item, chocolate);
    });

    test('the folding rules reach all the way through', () {
      // Arabic-Indic digits, ta marbuta as ha, and tatweel, all at once.
      expect(only('ميـاه نوفـا ٣٣٠').best!.item, water330);
    });

    test('nothing in the catalog scores nothing', () {
      final lines = matcher.match('محتاج مكنسة كهربائية');
      expect(lines.single.candidates, isEmpty);
      expect(lines.single.isNoise, isTrue);
    });
  });

  group('quantities', () {
    test('a leading count is the quantity', () {
      expect(only('3 كرتونة مياه نوفا 330').quantity, 3);
    });

    test('no count means one', () {
      expect(only('مياه نوفا 330 مل').quantity, 1);
    });

    test('a size is not a quantity', () {
      // 330 is glued to مل, so the count is 2 — not 330.
      expect(only('2 مياه نوفا 330 مل').quantity, 2);
    });

    test('Arabic-Indic digits count too', () {
      expect(only('٥ صابون لوكس').quantity, 5);
    });

    test('list numbering is not a quantity', () {
      // "1." is the bullet, "4" is the real count. Reading the marker as the
      // count would silently reorder every numbered list.
      final lines = matcher.match('1. 4 كرتونة مياه نوفا 500');
      expect(lines.single.quantity, 4);
    });

    test('a dash-numbered marker is not the quantity either', () {
      // "1- ٥ بكت" is the form real senders use most, and the dangerous one:
      // read the marker as the count and a five-pack order becomes one.
      final lines = matcher.match('1- ٥ صابون لوكس');
      expect(lines.single.quantity, 5);
    });

    test('a bare numbered line still defaults to one', () {
      final lines = matcher.match('2) صابون لوكس');
      expect(lines.single.quantity, 1);
    });
  });

  group('a real-shaped message', () {
    final message = '''
السلام عليكم ورحمة الله
معاك احمد من فرع المعادي
محتاج لو سمحت:
1. ٥ كرتونة مياه نوفا ٣٣٠
2. 3 علبة صابون لوكس
- شوكولاته جالاكسي 10
وشكرا جزيلا
01001234567
''';

    test('greetings, names, numbers and sign-offs are recognised as noise', () {
      final noise = matcher.match(message).where((l) => l.isNoise).map((l) => l.text);

      expect(noise, contains('السلام عليكم ورحمة الله'));
      expect(noise, contains('وشكرا جزيلا'));
      expect(noise, contains('01001234567'));
    });

    test('every real item is found with the right row and count', () {
      final found = {
        for (final line in matcher.match(message).where((l) => !l.isNoise))
          if (line.best != null && line.best!.score > 0.5)
            line.best!.item.id: line.quantity,
      };

      expect(found, {
        'water-330': 5,
        'soap-lux': 3,
        'choc': 10,
      });
    });
  });
}
