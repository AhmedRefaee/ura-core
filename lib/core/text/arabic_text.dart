/// Folds Arabic text into a form that can be compared literally.
///
/// Two people typing the same product name rarely produce the same bytes. The
/// same word arrives as "مياه" and "ميـاه", as "معلبة" and "معلبه", with or
/// without tashkeel, with Arabic-Indic digits or Western ones. None of those
/// differences mean anything to a reader, and all of them defeat `==`.
///
/// Everything here is lossy on purpose: after folding, "أ" and "ا" are the same
/// letter. That is exactly what makes matching work, and exactly why folded text
/// must never be shown back to anyone or stored as the real name.
class ArabicText {
  const ArabicText._();

  /// Marks that ride on top of a letter and carry no weight for matching:
  /// fatha, damma, kasra, shadda, sukun, the tanween forms, and the superscript
  /// alef. Also tatweel (ـ), which is pure typographic stretching.
  static final _diacritics = RegExp('[ً-ٰٕـ]');

  /// Anything that isn't an Arabic letter, a Latin letter or a digit becomes a
  /// separator. Punctuation, emoji and the direction marks that WhatsApp likes
  /// to sprinkle through a forwarded message all fall out here.
  static final _separators = RegExp('[^ء-يa-z0-9]+');

  /// Boundary between a digit and a Latin letter, in either direction —
  /// "30kg", "2crt", "3days", "4M" fuse the two with nothing for [_separators]
  /// to catch, since both sides belong to its "keep" class. Deliberately does
  /// NOT touch digit↔Arabic-letter boundaries — no evidence of that fusion in
  /// real messages, and touching it risks the well-tested Arabic path for no
  /// observed benefit.
  static final _digitLetterBoundary =
      RegExp(r'(?<=[0-9])(?=[a-z])|(?<=[a-z])(?=[0-9])');

  static const _letterFolds = {
    // Every alef with a seat, plus alef wasla, folds to bare alef.
    'آ': 'ا', // آ
    'أ': 'ا', // أ
    'إ': 'ا', // إ
    'ٱ': 'ا', // ٱ
    // Ta marbuta is written as ha at the end of a word about as often as not.
    'ة': 'ه', // ة → ه
    // Alef maqsura and ya are interchangeable in practice.
    'ى': 'ي', // ى → ي
    // Hamza carriers fold to their carrier letter.
    'ؤ': 'و', // ؤ → و
    'ئ': 'ي', // ئ → ي
    'ء': '', // ء on its own carries nothing for matching
  };

  /// Folds a string for comparison. The result keeps word boundaries as single
  /// spaces and is trimmed; it is never empty-padded.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final folded = _letterFolds[ch];
      if (folded != null) {
        buffer.write(folded);
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        // Arabic-Indic ٠-٩
        buffer.write(rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        // Extended Arabic-Indic ۰-۹, used in Persian/Urdu keyboards
        buffer.write(rune - 0x06F0);
      } else {
        buffer.write(ch);
      }
    }

    return buffer
        .toString()
        .replaceAll(_diacritics, '')
        .replaceAllMapped(_digitLetterBoundary, (_) => ' ')
        .replaceAll(_separators, ' ')
        .trim();
  }

  /// Folded words, in order, with empties dropped and the definite article
  /// removed.
  ///
  /// Dropping "ال" matters more here than any other single rule. A catalog row
  /// reads "عصير المانجو" and the person ordering writes "عصير مانجو"; those are
  /// the same product and, without this, not the same token. Arabic attaches
  /// the article to the word rather than standing it apart, so unlike English
  /// there is no whitespace to save us.
  static List<String> tokenize(String input) {
    final normalized = normalize(input);
    if (normalized.isEmpty) return const [];
    return [
      for (final token in normalized.split(' '))
        if (token.isNotEmpty) _stripArticle(token),
    ];
  }

  /// Removes a leading "ال" (or "وال") when enough word is left to still mean
  /// something. The length floor is what stops "الله" becoming "له" and short
  /// words collapsing into each other.
  static String _stripArticle(String word) {
    if (word.length >= 6 && word.startsWith('وال')) return word.substring(3);
    if (word.length >= 5 && word.startsWith('ال')) return word.substring(2);
    return word;
  }

  /// How alike two folded words are, 0 to 1, by shared character trigrams.
  ///
  /// This is the typo allowance. Exact equality catches the common case; this
  /// catches "شيكولاته" against "شوكولاته" and the like. Deliberately not an
  /// edit distance: trigrams are cheap, and against a 194-row catalog we score
  /// every row on every line.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.length < 3 || b.length < 3) return 0;
    final left = _trigrams(a);
    final right = _trigrams(b);
    if (left.isEmpty || right.isEmpty) return 0;
    final shared = left.intersection(right).length;
    return 2 * shared / (left.length + right.length);
  }

  static Set<String> _trigrams(String word) {
    final padded = '  $word ';
    return {
      for (var i = 0; i + 3 <= padded.length; i++) padded.substring(i, i + 3),
    };
  }
}
