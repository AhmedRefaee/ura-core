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

    test('a request for something unstocked survives as a line with no options',
        () {
      // Not noise. The sender asked for it, so the verifier has to see it —
      // dropping it silently is how an order loses a line nobody notices.
      final lines = matcher.match('محتاج مكنسة كهربائية');

      expect(lines.single.candidates, isEmpty);
      expect(lines.single.isNoise, isFalse);
      expect(lines.single.text, contains('مكنسة'));
    });

    test('a line with no word that could name a product is noise', () {
      expect(matcher.match('01001234567').single.isNoise, isTrue);
    });

    test('headers wrapped in asterisks are noise, but a bolded real order is not',
        () {
      final result = matcher.match('*Order for weekly*\n1/ 3 صابون لوكس');

      expect(result.first.isNoise, isTrue);
      expect(result.last.isNoise, isFalse);
      expect(result.last.best?.item, soap);
    });

    test('a fully-bolded real product line is not mistaken for a header', () {
      final line = only('*3 صابون لوكس*');

      expect(line.isNoise, isFalse);
      expect(line.best!.item, soap);
    });

    test('a header is still noise even when a stray number coincides with a catalog token',
        () {
      // "3days" splits into "3"+"days" (the digit/letter boundary fix). If
      // some unrelated row's name happens to contain a bare "3" (real
      // catalog example: "...مقاس 3"), that exact-matches and makes
      // matchedVocab non-empty — but a number alone can never pass the
      // sharesContent gate, so real scoring still finds nothing. The header
      // check has to be judged by that outcome, not by whether any
      // vocabulary overlapped at all before scoring ran.
      const plateSize3 = InventoryItem(
        id: 'plate-3',
        itemName: 'صحن ورق كرافت مقاس 3',
        quantity: 50,
        unit: 'كرتون',
        category: 'ادوات تقديم',
      );
      final withCollision = LocalItemMatcher([...inventory, plateSize3]);

      final line = withCollision
          .match('*Order for 3days*')
          .where((l) => !l.isNoise)
          .toList();

      // Would be non-empty and misreported as "nothing in the catalog" under
      // the old matchedVocab.isEmpty check; must be noise instead.
      expect(line, isEmpty);
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

    test('a slash-numbered marker is not the quantity either', () {
      // Common in English-language messages ("1/ item"). Deliberately using
      // different digits for the marker and the real count — "9/ 3 كرتون"
      // means 9 was a marker and 3 the count; if the marker leaked, it would
      // read as 9, and a test built on equal digits couldn't catch that.
      final lines = matcher.match('9/ 3 كرتون صابون لوكس');
      expect(lines.single.quantity, 3);
    });

    test('a weight before the product is a count, after it is a size', () {
      // Identical shape, opposite meaning. What separates them is whether a
      // product has been named yet.
      expect(only('3 كجم صابون لوكس').quantity, 3);
      expect(only('صابون لوكس 3 كجم').quantity, 1);
    });

    test('a number inside the name is not a count', () {
      // "٥ نجوم" is five-star, a grade, not five of anything. Reading it as a
      // count silently multiplies the order.
      final lines = matcher.match('مياه نوفا 330 مل 5 نجوم');
      expect(lines.single.quantity, 1);
    });

    test('a trailing number is the count', () {
      expect(only('صابون لوكس 4').quantity, 4);
    });

    test('a bare numbered line still defaults to one', () {
      final lines = matcher.match('2) صابون لوكس');
      expect(lines.single.quantity, 1);
    });

    test('an English packaging count is recognised, once split', () {
      expect(only('2crt صابون لوكس').quantity, 2);
    });

    test('an English weight unit before the product is a count', () {
      expect(only('3kg صابون لوكس').quantity, 3);
    });

    test('an English hedge word does not get counted as the product', () {
      expect(only('please 2 kg صابون لوكس').quantity, 2);
    });
  });

  group('English and bilingual input', () {
    // Styled after the real catalog's coffee/tea/milk rows, which is what
    // exposed the cross-department alias collisions this table now excludes.
    const darkCoffee = InventoryItem(
      id: 'coffee-dark',
      itemName: 'بن هرري محمص غامق',
      quantity: 20,
      unit: 'كجم',
      category: 'قهوة',
    );
    const arabicaBeans = InventoryItem(
      id: 'coffee-beans',
      itemName: 'حبوب قهوة ارابيكا',
      quantity: 20,
      unit: 'كجم',
      category: 'قهوة',
    );
    const greenTeaAhmad = InventoryItem(
      id: 'tea-green-ahmad',
      itemName: 'احمد شاي اخضر',
      quantity: 30,
      unit: 'بكت',
      category: 'شاي',
    );
    const greenTeaRabie = InventoryItem(
      id: 'tea-green-rabie',
      itemName: 'الربيع شاي اخضر',
      quantity: 30,
      unit: 'بكت',
      category: 'شاي',
    );
    const redTeaTwinings = InventoryItem(
      id: 'tea-red-twinings',
      itemName: 'توينجز شاي احمر',
      quantity: 30,
      unit: 'بكت',
      category: 'شاي',
    );
    const bonnySachet = InventoryItem(
      id: 'milk-bonny-sachet',
      itemName: 'حليب بوني شفرات',
      quantity: 40,
      unit: 'كرتون',
      category: 'البان',
    );
    const bonnyCarton = InventoryItem(
      id: 'milk-bonny-carton',
      itemName: 'حليب بوني كامل الدسم',
      quantity: 40,
      unit: 'علبة',
      category: 'البان',
    );
    const plate = InventoryItem(
      id: 'plate-big',
      itemName: 'صحن بلاستيك مستطيل كبير',
      quantity: 100,
      unit: 'كرتون',
      category: 'ادوات تقديم',
    );

    final bilingualInventory = [
      darkCoffee, arabicaBeans, greenTeaAhmad, greenTeaRabie, redTeaTwinings,
      bonnySachet, bonnyCarton, plate,
    ];
    final bilingualMatcher = LocalItemMatcher(bilingualInventory);

    RequestLine onlyOf(String message) {
      final lines =
          bilingualMatcher.match(message).where((l) => !l.isNoise).toList();
      expect(lines, hasLength(1), reason: 'expected exactly one real line');
      return lines.single;
    }

    test('a bare English category word stays broadly ambiguous, like its Arabic equivalent', () {
      final line = onlyOf('coffee');

      expect(line.candidates.length, greaterThanOrEqualTo(2));
      expect(line.best!.score, lessThan(0.7));
    });

    test('green tea matches every green-tea row, ambiguously', () {
      final line = onlyOf('green tea');

      expect(line.candidates.map((c) => c.item.id),
          containsAll(['tea-green-ahmad', 'tea-green-rabie']));
    });

    test('red tea resolves confidently — only one row is both red and tea', () {
      expect(onlyOf('red tea').best!.item, redTeaTwinings);
    });

    test('a brand plus product narrows an otherwise-ambiguous English noun', () {
      final line = onlyOf('bonny milk');

      expect(line.candidates.map((c) => c.item.id),
          containsAll(['milk-bonny-sachet', 'milk-bonny-carton']));
    });

    test('case does not matter for English tokens', () {
      expect(onlyOf('COFFEE').candidates, isNotEmpty);
      expect(onlyOf('Coffee').candidates.length,
          onlyOf('coffee').candidates.length);
    });

    test('a product genuinely absent from the catalog has no candidates', () {
      // Deliberately excludes "coffee mate": it shares the word "coffee",
      // which is a correct alias needed for "Black coffee"/"coffee beans" to
      // work — so it legitimately surfaces low-score coffee suggestions
      // rather than nothing. That's safe (well under the 0.65 auto-accept
      // threshold, never silently added), just not literally empty.
      for (final query in [
        'nescafe',
        'nespresso capsule',
        'cardamom',
        'water',
        'fresh fruit',
      ]) {
        expect(bilingualMatcher.match(query).single.candidates, isEmpty,
            reason: query);
      }
    });

    test('a line sharing only a loose word gets low-confidence suggestions, never a silent match', () {
      final line = onlyOf('coffee mate');
      expect(line.candidates, isNotEmpty);
      expect(line.best!.score, lessThan(0.65));
    });

    test('an unrelated adjective does not pull in a wrong department', () {
      // "big" must not surface the plate row for an unrelated request — no
      // cup product exists, so this must fall through to unmatched.
      final line = onlyOf('only curve big cups');
      expect(line.candidates, isEmpty);
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

    test('greetings, sign-offs and bare numbers are recognised as noise', () {
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
