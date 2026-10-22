/// Undoes two ways the pdf package garbles right-to-left text when the base
/// font lacks some characters -- Noto Sans Arabic, the سند font, has no
/// brackets, "*", "/", "%" or Latin letters at all.
///
/// The pdf package draws every character the base font lacks as its own
/// one-character span in a fallback font, and runs bidi on each span alone:
///  * a lone "(" has no direction of its own, so it is never mirrored, and
///    "(40 عبوة)" prints as ")40 عبوة(";
///  * the spans of a Latin word are laid out right-to-left one letter at a
///    time, so "UHV" prints as "VHU".
///
/// This resolves directions the way the Unicode bidi algorithm would for a
/// right-to-left paragraph (UAX #9, the parts that matter here: W7, N0,
/// N1/N2), mirrors every bracket that comes out right-to-left, and reverses
/// each left-to-right run so the right-to-left layout puts it back the right
/// way round.
///
/// [baseFontHas] says which characters the base font covers. Whatever it
/// covers already goes through bidi in one piece and comes out right, so a
/// font with brackets and Latin (e.g. Tahoma in tests) gets [text] back
/// unchanged.
String fixRtlTextForPdf(String text, bool Function(int rune) baseFontHas) {
  final mirrorBrackets = !baseFontHas(0x28);
  final reverseLtr = !baseFontHas(0x41);
  if (!mirrorBrackets && !reverseLtr) return text;

  final runes = text.runes.toList();
  final ltr = _resolve(runes);
  final out = <int>[
    for (var i = 0; i < runes.length; i++)
      mirrorBrackets && ltr[i] == false && _mirror.containsKey(runes[i]) ? _mirror[runes[i]]! : runes[i],
  ];
  if (!reverseLtr) return String.fromCharCodes(out);

  // A left-to-right run: from a Latin letter to the last left-to-right
  // character before anything right-to-left. Neutrals inside it go with it.
  var i = 0;
  while (i < out.length) {
    if (ltr[i] != true || !_isLatinLetter(runes[i])) {
      i++;
      continue;
    }
    var end = i;
    for (var j = i + 1; j < out.length && ltr[j] != false; j++) {
      if (ltr[j] == true) end = j;
    }
    // Units the pdf package will lay out right-to-left: each character the
    // base font lacks on its own, each stretch of ones it has together
    // (its own bidi keeps "10" reading "10").
    final units = <List<int>>[];
    for (var k = i; k <= end; k++) {
      if (!baseFontHas(out[k]) || units.isEmpty || !baseFontHas(units.last.last)) {
        units.add([out[k]]);
      } else {
        units.last.add(out[k]);
      }
    }
    out.replaceRange(i, end + 1, [for (final u in units.reversed) ...u]);
    i = end + 1;
  }
  return String.fromCharCodes(out);
}

const _mirror = {
  0x28: 0x29, 0x29: 0x28, // ( )
  0x5B: 0x5D, 0x5D: 0x5B, // [ ]
  0x7B: 0x7D, 0x7D: 0x7B, // { }
};

/// Per character: true = left-to-right, false = right-to-left, null = a
/// neutral that isn't a bracket (left for the pdf package's own bidi).
List<bool?> _resolve(List<int> runes) {
  // Strong types. W7: a digit takes the direction of the nearest letter
  // before it, right-to-left at the start of the text.
  final types = List<bool?>.filled(runes.length, null);
  var lastLetterLtr = false;
  for (var i = 0; i < runes.length; i++) {
    final c = runes[i];
    if (_isLatinLetter(c)) {
      types[i] = lastLetterLtr = true;
    } else if (_isArabicLetter(c)) {
      types[i] = lastLetterLtr = false;
    } else if (_isDigit(c)) {
      types[i] = lastLetterLtr;
    }
  }

  bool? strongBefore(int i) {
    for (var j = i - 1; j >= 0; j--) {
      if (types[j] != null) return types[j];
    }
    return null;
  }

  bool? strongAfter(int i) {
    for (var j = i + 1; j < runes.length; j++) {
      if (types[j] != null) return types[j];
    }
    return null;
  }

  // N0: a bracket pair with right-to-left text inside is right-to-left;
  // with only left-to-right text inside, it follows what's before it.
  // Pairs are resolved in order of their opening bracket, and each resolved
  // bracket then counts as strong for the pairs after it.
  final pairs = <(int, int)>[];
  final open = <int>[];
  for (var i = 0; i < runes.length; i++) {
    final c = runes[i];
    if (c == 0x28 || c == 0x5B || c == 0x7B) {
      open.add(i);
    } else if (c == 0x29 || c == 0x5D || c == 0x7D) {
      final k = open.lastIndexWhere((o) => _mirror[runes[o]] == c);
      if (k >= 0) {
        pairs.add((open[k], i));
        open.removeRange(k, open.length);
      }
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (o, c) in pairs) {
    final inside = types.sublist(o + 1, c);
    final bool dir;
    if (inside.contains(false)) {
      dir = false;
    } else if (inside.contains(true)) {
      dir = strongBefore(o) ?? false;
    } else {
      continue;
    }
    types[o] = types[c] = dir;
  }

  // N1/N2: any other bracket goes with its surroundings when both sides
  // agree, right-to-left otherwise (and at the start and end of the text).
  for (var i = 0; i < runes.length; i++) {
    if (types[i] == null && _mirror.containsKey(runes[i])) {
      types[i] = strongBefore(i) == true && strongAfter(i) == true;
    }
  }
  return types;
}

bool _isLatinLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7);

bool _isDigit(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x660 && c <= 0x669) || (c >= 0x6F0 && c <= 0x6F9);

bool _isArabicLetter(int c) =>
    ((c >= 0x0590 && c <= 0x08FF) && !_isDigit(c) && c != 0x60C && c != 0x61B && c != 0x61F && c != 0x66A) ||
    (c >= 0xFB1D && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF);
