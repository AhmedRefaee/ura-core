// Tests the dictionary's shape in isolation, before it ever reaches the
// matcher. The negative cases matter more than the positive ones: they pin
// down what must NEVER resolve, so a future well-meaning addition can't
// quietly reintroduce a false match this file already ruled out.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/data/english_alias.dart';

void main() {
  group('known mappings', () {
    // Expected values are the FOLDED form (ة→ه etc.) — arabicFor() returns
    // catalog-index tokens, already run through ArabicText.tokenize(), not
    // the raw dictionary spelling.
    test('a product noun resolves to its Arabic catalog word(s)', () {
      expect(EnglishAlias.arabicFor('coffee'), containsAll(['قهوه', 'بن']));
      expect(EnglishAlias.arabicFor('tea'), ['شاي']);
      expect(EnglishAlias.arabicFor('milk'), ['حليب']);
    });

    test('chocolate resolves to both catalog spellings', () {
      expect(EnglishAlias.arabicFor('chocolate'),
          containsAll(['شيكولاته', 'شوكولاته']));
    });

    test('a brand transliteration resolves', () {
      expect(EnglishAlias.arabicFor('bonny'), ['بوني']);
      expect(EnglishAlias.arabicFor('twinings'), ['توينجز']);
    });

    test('lookups are keyed lowercase', () {
      // Callers are expected to lowercase first (ArabicText.normalize already
      // does this before any token reaches here) — this just documents that
      // the table itself does not case-fold on its own.
      expect(EnglishAlias.arabicFor('COFFEE'), isEmpty);
      expect(EnglishAlias.arabicFor('coffee'), isNotEmpty);
    });
  });

  group('must stay empty — no such product in the catalog', () {
    // This test used to assert that nescafe, nespresso and coffeemate resolve
    // to nothing. All three are stocked — نسكافي، كبسولات نسبرسو، كوفي ميت —
    // and were simply absent from the 99-row export the list was first vetted
    // against. What genuinely is not carried is the coffee brand nobody asked
    // for by a name we hold.
    test('a brand the catalogue does not carry resolves to nothing', () {
      for (final word in ['starbucks', 'illy', 'lavazza']) {
        expect(EnglishAlias.arabicFor(word), isEmpty, reason: word);
      }
    });

    test('«كوفي» is not aliased despite كوفي ميت being stocked', () {
      // It sits on filters, coffee, tea and chocolate rows. Only «ميت», which
      // is unique to the one row, carries the coffeemate lookup.
      expect(EnglishAlias.arabicFor('coffeemate'), ['ميت']);
      expect(EnglishAlias.arabicFor('coffeemate'), isNot(contains('كوفي')));
    });

    test('unstocked products resolve to nothing', () {
      // 'cardamom' and 'water' used to be asserted here too, on the belief
      // that neither was carried. Both were in the catalogue all along —
      // missing only from the 99-row export this list was first vetted
      // against. 'curve' (a cup brand nobody stocks) and 'fruit' stay.
      for (final word in ['curve', 'fruit', 'pepsi', 'ice']) {
        expect(EnglishAlias.arabicFor(word), isEmpty, reason: word);
      }
    });
  });

  // Every one of these came from a real request line that previously matched
  // nothing at all. Each target was checked against the full 195-row export
  // and appears in exactly one category, so none can pull a wrong-department
  // row — the vetting rule english_alias.dart sets out.
  group('English words for things that are stocked', () {
    test('product nouns resolve to the catalogue word', () {
      expect(EnglishAlias.arabicFor('cardamom'), contains('هيل'));
      expect(EnglishAlias.arabicFor('cups'), contains('كاسات'));
      expect(EnglishAlias.arabicFor('capsule'), contains('كبسولات'));
      expect(EnglishAlias.arabicFor('filter'), contains('فلتر'));
      expect(EnglishAlias.arabicFor('plates'), contains('صحن'));
    });

    test('water resolves despite the catalogue spelling it مياة', () {
      // Normalisation folds ة to ه, so the stored spelling and the one a
      // customer types are the same token by the time they are compared.
      expect(EnglishAlias.arabicFor('water'), isNotEmpty);
    });

    test('singular and plural both resolve', () {
      for (final pair in [
        ['cup', 'cups'],
        ['plate', 'plates'],
        ['spoon', 'spoons'],
        ['fork', 'forks'],
      ]) {
        expect(EnglishAlias.arabicFor(pair[0]), isNotEmpty, reason: pair[0]);
        expect(EnglishAlias.arabicFor(pair[1]), isNotEmpty, reason: pair[1]);
      }
    });

    test('brand transliterations resolve, misspellings included', () {
      expect(EnglishAlias.arabicFor('nespresso'), contains('نسبرسو'));
      // The spelling a real sender actually used.
      expect(EnglishAlias.arabicFor('nespersso'), contains('نسبرسو'));
      expect(EnglishAlias.arabicFor('nesscafe'), contains('نسكافي'));
      expect(EnglishAlias.arabicFor('lipton'), contains('ليبتون'));
      expect(EnglishAlias.arabicFor('nova'), contains('نوفا'));
      expect(EnglishAlias.arabicFor('kitkat'), containsAll(['كيت', 'كات']));
    });
  });

  group('must stay empty — cross-department collision', () {
    // 'اسود' (black) sits on both tea rows and black-plastic-cutlery rows;
    // 'كبير'/'صغير' (big/small) sit on both chocolate rows and disposable
    // plate rows. Aliasing either would surface a wrong-department candidate
    // for a line that should fall through to unmatched instead — see the
    // exclusion notes in english_alias.dart.
    test('black is not aliased', () {
      expect(EnglishAlias.arabicFor('black'), isEmpty);
    });

    test('big and small are not aliased', () {
      expect(EnglishAlias.arabicFor('big'), isEmpty);
      expect(EnglishAlias.arabicFor('small'), isEmpty);
    });
  });
}
