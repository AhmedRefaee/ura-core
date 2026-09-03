import '../../../core/text/arabic_text.dart';

/// Catalog vocabulary an English word can also mean.
///
/// Grounded, not translated: every value here is a word verified to appear
/// literally in the real inventory export. A word with no entry here simply
/// yields nothing — that absence *is* the mechanism that keeps a request for
/// something genuinely unstocked (بيبسي, ثلج, car tyres, fresh fruit) falling
/// through to the unmatched/custom-item flow instead of being forced onto the
/// nearest unrelated row. Do not add an entry for a word "because it would be
/// helpful" — add it only after confirming the target word is in the catalog
/// and checking every row it appears in (see the vetting note on adjectives
/// below).
///
/// **This list was once vetted against a 99-row export and is now vetted
/// against the full 195.** Several words this file previously named as
/// "genuinely unstocked" — nescafe, cardamom, water, cups — turned out to be
/// stocked all along; they were missing from the smaller export, not from the
/// business. If you are about to conclude that something is not carried,
/// confirm it against a current export rather than against this comment.
class EnglishAlias {
  const EnglishAlias._();

  /// Folded English token -> catalog vocabulary tokens it can resolve to,
  /// pre-tokenized once so a lookup costs one map access, not a re-fold.
  static final Map<String, List<String>> _resolved = {
    for (final entry in _aliases.entries)
      entry.key: [for (final w in entry.value) ...ArabicText.tokenize(w)],
  };

  static List<String> arabicFor(String englishToken) =>
      _resolved[englishToken] ?? const [];

  static const Map<String, List<String>> _aliases = {
    // --- product / category nouns ---
    'coffee': ['قهوة', 'بن'],
    'beans': ['حبوب'],
    'tea': ['شاي'],
    'milk': ['حليب'],
    'sugar': ['سكر'],
    'nuts': ['مكسرات'], 'nut': ['مكسرات'],
    'dates': ['تمر'], 'date': ['تمر'],
    // Catalog spells this both ways (item names use ي, the category field
    // uses و) — list both so full name-token weight is reachable either way.
    'chocolate': ['شيكولاتة', 'شوكولاتة'], 'choc': ['شيكولاتة', 'شوكولاتة'],
    'ginger': ['زنجبيل'],
    'saffron': ['زعفران'],
    'juice': ['عصير'],
    'cardamom': ['هيل'],
    'water': ['مياة'],
    'cup': ['كاسات'], 'cups': ['كاسات'],
    'capsule': ['كبسولات'], 'capsules': ['كبسولات'],
    'filter': ['فلتر'], 'filters': ['فلتر'],
    'plate': ['صحن'], 'plates': ['صحن'],
    'spoon': ['ملاعق'], 'spoons': ['ملاعق'],
    'fork': ['شوكة'], 'forks': ['شوكة'],
    'knife': ['سكينة'], 'knives': ['سكينة'],
    'lid': ['غطاء'], 'lids': ['غطاء'],
    'stirrer': ['محرك'], 'stirrers': ['محرك'],

    // --- descriptive adjectives, vetted against every row they appear in
    //     (see exclusions below for what was deliberately left out) ---
    'dark': ['غامق'], 'roast': ['محمص'], 'roasted': ['محمص'],
    'light': ['قليل'],
    'whole': ['كامل'], 'fullfat': ['كامل'],
    'green': ['اخضر'],
    'red': ['احمر'],
    'mixed': ['مشكل', 'متنوع'], 'mix': ['مشكل', 'متنوع'],
    'ground': ['مطحون'],

    // --- brand transliterations, each confirmed against the real catalog ---
    'marai': ['المراعي'], 'almarai': ['المراعي'],
    'nadec': ['نادك'],
    'bonny': ['بوني'], 'bonnie': ['بوني'],
    'twinings': ['توينجز'],
    'ahmad': ['احمد'], 'ahmed': ['احمد'],
    'rabie': ['الربيع'], 'rabee': ['الربيع'],
    'qassim': ['القصيم'], 'qaseem': ['القصيم'], 'qassem': ['القصيم'],
    'galaxy': ['جلاكسي'],
    'snickers': ['سنيكرز'],
    'twix': ['تويكس'],
    'godiva': ['جوديفاء'],
    'kitkat': ['كيت كات'],
    'nescafe': ['نسكافي'], 'nesscafe': ['نسكافي'],
    // The misspelling is the one real senders actually wrote.
    'nespresso': ['نسبرسو'], 'nespersso': ['نسبرسو'],
    'nesquik': ['نسكويك'],
    'nova': ['نوفا'],
    'lipton': ['ليبتون'],
    'perrier': ['بيريه'],
    'melitta': ['ماليتا'], 'malita': ['ماليتا'],
    'dunkin': ['دانكن'],
    'luna': ['لونا'],
    // Deliberately 'ميت' alone, not 'كوفي ميت'. «كوفي» spans four categories —
    // مستر كوفي filters, كوفي هوليك coffee, كوفيك tea AND chocolate — so
    // aliasing it would drag half the catalogue in. «ميت» sits on one row.
    'coffeemate': ['ميت'], 'coffemate': ['ميت'],
  };

  // Deliberately excluded, and why — vetted by reading every catalog row the
  // target Arabic word appears on:
  //
  // 'black' -> 'اسود': appears on tea rows AND black-plastic-cutlery rows.
  // "Black coffee" is an idiom anyway (no catalog concept for it); aliasing
  // would surface a wrong-department tea row for zero benefit.
  //
  // 'small'/'large'/'big' -> 'صغير'/'كبير': appear on chocolate rows AND
  // disposable-plate rows. Aliasing 'big' would make "big cups" (which must
  // fall through to unmatched — no cup product exists) surface a large
  // rectangular plate as a spurious candidate.
  //
  // Before adding a new DESCRIPTIVE ADJECTIVE alias (nouns/brands are lower
  // risk), grep the real inventory export for the Arabic target and read
  // every row it's attached to. If the rows span product families an English
  // speaker wouldn't conflate — a color/size word shared between a beverage
  // and a disposable/plasticware item is the failure mode found here — leave
  // it out. A wrong-department candidate costs a confusing verifier tap for
  // no offsetting benefit.
}
