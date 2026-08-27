// Folding rules, pinned against the ways the same product name actually
// arrives in a forwarded WhatsApp message.
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/text/arabic_text.dart';

void main() {
  group('normalize', () {
    test('every alef seat folds to bare alef', () {
      expect(ArabicText.normalize('أحمد'), 'احمد');
      expect(ArabicText.normalize('إبريق'), 'ابريق');
      expect(ArabicText.normalize('آيس'), 'ايس');
    });

    test('ta marbuta and ha are the same ending', () {
      expect(ArabicText.normalize('معلبة'), ArabicText.normalize('معلبه'));
    });

    test('alef maqsura and ya are the same letter', () {
      expect(ArabicText.normalize('مصطفى'), ArabicText.normalize('مصطفي'));
    });

    test('tashkeel is dropped', () {
      expect(ArabicText.normalize('مِيَاه'), 'مياه');
    });

    test('tatweel stretching is dropped', () {
      expect(ArabicText.normalize('ميـــاه'), 'مياه');
    });

    test('Arabic-Indic digits become Western ones', () {
      expect(ArabicText.normalize('٣٣٠ مل'), '330 مل');
      expect(ArabicText.normalize('۵۰۰'), '500');
    });

    test('punctuation and emoji become separators', () {
      expect(ArabicText.normalize('مياه، نوفا! 🙏'), 'مياه نوفا');
    });

    test('whitespace collapses and the result is trimmed', () {
      expect(ArabicText.normalize('  مياه   نوفا \n\n 330  '), 'مياه نوفا 330');
    });

    test('Latin is lowercased, and a digit/letter boundary is inserted', () {
      // "500ml" fused would be invisible to quantity detection downstream —
      // neither a bare number nor a bare unit word.
      expect(ArabicText.normalize('Nova Water 500ML'), 'nova water 500 ml');
    });

    test('a digit/letter boundary splits in either direction', () {
      expect(ArabicText.normalize('30kg'), '30 kg');
      expect(ArabicText.normalize('3days'), '3 days');
    });

    test('Arabic-letter/digit fusion is left alone', () {
      // Deliberate scope boundary: only Latin letters get a digit boundary.
      // No evidence real messages fuse a digit directly onto an Arabic word
      // the way "30kg" fuses onto a Latin one.
      expect(ArabicText.normalize('٣كجم'), '3كجم');
    });

    test('the two spellings a rep actually types collapse together', () {
      expect(
        ArabicText.normalize('مِيــاه معلبة ٣٣٠'),
        ArabicText.normalize('مياه معلبه 330'),
      );
    });
  });

  group('tokenize', () {
    test('splits on any separator run', () {
      expect(ArabicText.tokenize('مياه نوفا، 330 مل'), ['مياه', 'نوفا', '330', 'مل']);
    });

    test('the definite article is dropped so ال is not a difference', () {
      // A catalog row says "عصير المانجو"; the person ordering writes
      // "عصير مانجو". Same product, and Arabic glues the article on with no
      // space to separate it.
      expect(ArabicText.tokenize('المانجو'), ArabicText.tokenize('مانجو'));
      expect(ArabicText.tokenize('عصير التفاح'), ['عصير', 'تفاح']);
      expect(ArabicText.tokenize('والقصيم'), ['قصيم']);
    });

    test('a short word keeps its ال rather than collapsing to nothing', () {
      // "الله" must not become "له"; two letters left is not a word.
      expect(ArabicText.tokenize('الله'), ['الله']);
    });

    test('an empty or punctuation-only string has no tokens', () {
      expect(ArabicText.tokenize('   '), isEmpty);
      expect(ArabicText.tokenize('!!! ---'), isEmpty);
    });

    test('a fused Latin quantity and unit split into two tokens', () {
      // Otherwise "30kg" is invisible to quantity detection: it's neither a
      // bare number nor a bare unit word, just one opaque blob.
      expect(ArabicText.tokenize('2crt'), ['2', 'crt']);
      expect(ArabicText.tokenize('5bag'), ['5', 'bag']);
    });

    test('a fused Arabic-Indic digit and Arabic word stays one token', () {
      // Locks in the deliberate scope boundary: only Latin fusion is split.
      expect(ArabicText.tokenize('٣كجم'), ['3كجم']);
    });
  });

  group('similarity', () {
    test('identical words are 1', () {
      expect(ArabicText.similarity('صابون', 'صابون'), 1);
    });

    test('a one-letter typo still scores high', () {
      expect(ArabicText.similarity('شوكولاته', 'شيكولاته'), greaterThan(0.6));
    });

    test('unrelated words score low', () {
      expect(ArabicText.similarity('صابون', 'مياه'), lessThan(0.2));
    });

    test('very short words are not fuzzy-matched at all', () {
      // Two-letter words share too much by chance; a false positive here puts
      // the wrong item in somebody's order.
      expect(ArabicText.similarity('مل', 'كل'), 0);
    });
  });
}
