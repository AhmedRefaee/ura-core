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
    test('unstocked coffee-adjacent brands resolve to nothing', () {
      for (final word in ['nescafe', 'nespresso', 'coffeemate']) {
        expect(EnglishAlias.arabicFor(word), isEmpty, reason: word);
      }
    });

    test('unstocked products resolve to nothing', () {
      for (final word in ['cardamom', 'water', 'curve', 'fruit']) {
        expect(EnglishAlias.arabicFor(word), isEmpty, reason: word);
      }
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
