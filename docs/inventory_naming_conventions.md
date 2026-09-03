# Inventory naming conventions & data-cleaning rules

How to read the Arabic item names in `public.inventory` and split them into the
structured columns. Written 2026-09-02 while backfilling the 195-item catalogue,
so that the next pass doesn't have to re-derive any of it.

**Read this before touching `brand`, `variety`, `packaging_size`, or
`packaging_size_unit` on any row.**

---

## 1. Where each piece of information belongs

An item name in this catalogue typically encodes four separate things at once.
They go to four different places:

| What it is | Example inside a name | Where it belongs |
|---|---|---|
| Who makes it | `المراعي`, `ليبتون`, `نوفا` | `brand` |
| Which variant | `كامل الدسم`, `مطحون`, `أخضر` | `variety` |
| Size of **one piece** | `330 مل`, `1 كجم`, `8 اونص` | **stays in `item_name`** |
| How many pieces **per pack** | `شد 24`, `1000 حبة`, `100 خيط` | `packaging_size` + `_unit` |

### The two rules that are easy to get backwards

**`item_name` is never edited.** Not to strip sizes, not to fix typos, not to
normalise spelling. Every rule below is *additive* — it fills empty columns and
leaves the name byte-for-byte identical. This is deliberate: the AI that matches
customer messages reads `item_name` and nothing else (see
`LocalItemMatcher` / `HybridItemMatchRepository`), so shortening names would
degrade matching until the matcher is rewired to read these columns. Until that
work is done, names stay.

**`packaging_size` is a piece COUNT, not a weight.** The size of one piece
(`330 مل`) stays in the name. `packaging_size` answers only "how many pieces
come in one pack". This was the owner's explicit decision, chosen over storing
the piece weight there.

---

## 2. The `A * B` rule

Names frequently carry two numbers multiplied: `شد 6 *40 حبة`,
`شد 50*10 حبة`, `16*20`.

> **The smaller number is how many packs are in the carton.**
> **The larger number is how many pieces are in each pack.**
>
> `packaging_size` takes **the larger number**.

Position is *not* reliable — the larger number appears first in some names and
second in others. Only relative size decides.

| Name fragment | Carton holds | Each pack holds | `packaging_size` |
|---|---|---|---|
| `شد 6 *40 حبة` (تويكس) | 6 packs | 40 pieces | **40** |
| `شد 18 *36 حبة` (كيت كات) | 18 packs | 36 pieces | **36** |
| `شد 50*10 حبة` (صحن بلاستيك) | 10 bags | 50 plates | **50** |
| `شد 40*25 حبة` (صحن ورق كرافت) | 25 bags | 40 plates | **40** |
| `16*20` (ليبتون هارموني) | 16 packs | 20 bags | **20** |
| `شد 1*80 شد 9` (فلتر ماليتا صغير) | 9 packs | 80 filters | **80** |

The last shape — `شد 1*B شد C` — puts the pack count in a **second** `شد`
at the end. Still the same rule: the largest number is the piece count.

### Three exceptions

**A. One side carries a weight or volume unit.** Then that side is the piece
size (leave it in the name) and the *other* side is the count, regardless of
which is larger.

| Name | Reading | `packaging_size` |
|---|---|---|
| `شد 10*500 جم` (مبيض قهوة) | 10 bags of 500 g | **10** |
| `6 حبة *21 جم` (شيبسي ليز) | 6 pieces of 21 g | **6** |
| `50 حبة 15 جم` (حليب بوني شفرات) | 50 pieces of 15 g | **50** |
| `شد 24 حبة 330 مل` (مياه بيريه) | 24 bottles of 330 ml | **24** |

Weight/volume markers to watch for: `جم` `جرام` `كجم` `كيلو` `مل` `لتر`
`اونص` `جالون`.

**B. The number is part of the product's identity.** Leave `packaging_size`
empty.

- `نسكافيه 3*1` — "3-in-1" instant coffee. The real count comes from the
  separate `25 ظرف` later in the same name.
- `فلتر قهوة انيشن 1*2` / `1*4` — standard filter-cone sizes (the Melitta
  1x2 / 1x4 convention), not quantities. These get `variety = "مقاس 1×2"`.

**C. The number is a supplier code.** Leave everything empty.
Shapes seen: `كود 44/25`, `رقم 20/25`, a bare `39/25`, `4M`, `مقاس 18`,
`مقاس 3`. Grades like `2 نجوم` / `4 نجوم` / `5 نجوم` belong in `variety`,
not in packaging.

---

## 3. Counting vocabulary

`packaging_size_unit` should reuse the word the name itself uses. Observed in
this catalogue:

| Term | Means | Typical products |
|---|---|---|
| `حبة` | a single piece | cups, plates, cutlery, bottles, chocolate bars |
| `خيط` | a tea bag (lit. "string") | tea |
| `كيس` | a bag/sachet | tea, powders |
| `ظرف` | a sachet/stick | sugar sticks, instant coffee |
| `شد` | a pack/bundle — a **prefix announcing a count**, not a unit itself | everywhere |

`شد` is a marker, never a value. `شد 500 حبة` means "a pack of 500 pieces" →
`500` + `حبة`. Do not write `شد` into `packaging_size_unit`.

Note the separate `unit` column already on the table (`كرتون`, `كيس`, `بكت`,
`علبة`, `حبة`, `كجم`, `شدة`, `قاروة`, `عبوة`) — that is *how the item is
counted when ordering*, and is unrelated to `packaging_size_unit`. Don't
conflate them.

> **Sourcing note.** `شد`, `بكت`, and `ظرف` in these senses are Saudi wholesale
> trade jargon — a web search in Sept 2026 found no authoritative reference for
> them (results were carton-manufacturing pages and the unrelated car-import
> idiom "شد بلد"). Only `كرتون` and `درزن` are documented generally. Everything
> in this table was derived from the catalogue itself and confirmed by the
> business owner. Treat the owner as the authority, not the internet.

---

## 4. Brand vs. variety vs. customer

**Brand** is the manufacturer or the supplier the item is bought as. When a name
ends in `- <name>` that trailing name is usually the supplier:
`تمر سكري مغلف - اطايب التمور`, `معمول توفي - الضيف`.

**Variety** is everything that distinguishes this item from others of the same
brand: `كامل الدسم` / `قليل الدسم`, roast level (`محمص وسط`, `مطحون غامق`),
origin (`إثيوبي`, `كولمبي`), colour and construction (`سنجل`, `دبل`, `مضلع`),
flavour (`برتقال`, `مانجو`).

**A customer's name is not a brand.** Some stock is printed with a client's
logo and exists only for them — e.g. `كاسات بنك المنشات`. Bank Al-Inshaat is
the *customer*, not the manufacturer. That belongs in `variety` (or
`description`) phrased as what it is: `بشعار بنك المنشآت`. Putting it in
`brand` would corrupt the duplicate-detection rule, which treats brand as part
of an item's identity.

**Origin vs. brand can collide.** `خلاص القصيم فاكيوم - 500 جم - الضيف` carries
both: القصيم is where the dates come from, الضيف is the supplier. Supplier wins
`brand`; origin goes into `variety`.

---

## 5. Known typos in the live data

These are **not** corrected by this process — names are never edited — but they
are real and worth knowing about:

| Row | Written | Should be |
|---|---|---|
| `قهوة لدن 500 حم` | `حم` | `جم` |
| `مكسرات مشكلة - ا كجم` | `ا` | `1` |
| `نسكويك بودرة كبير - ا كيلو` | `ا` | `1` |
| `شاي كريشو مغلف 100 حبه` | `حبه` | `حبة` |
| `تمر سكري جلاكسي  39/25` | double space | single |
| `مياة نوفا  1.50 لتر` | double space | single |

Also: the category is spelled `مياة` throughout (standard is `مياه`), and one
row (`كبسولات نسبرسو`) has no category at all.

---

## 6. Doing this again

1. **Export.** Pull `id, item_name, unit, category` for every live row:
   ```
   npx supabase db query --linked "SELECT ... FROM inventory WHERE archived_at IS NULL"
   ```
2. **Classify** into a keyed table of `(brand, variety, packaging_size, packaging_size_unit)`,
   flagging every judgement call with a one-line reason.
3. **Verify mechanically** before showing anyone: assert every row is covered,
   that no id is missing or extra, and that every `A*B` row equals
   `max(A, B)` unless it is a documented exception. Catching a positional
   mistake here is what caught the two plate rows.
4. **Publish a review page** and let the owner correct it. Do not write first
   and fix later — the owner knows the physical cartons and you do not.
5. **Apply** via `inventory_bulk_update_items`, never a raw table write — the
   RPC enforces the role check, the quantity rule, and writes audit rows.
6. **Re-verify** the applied counts against the proposal.

### Sanity checks worth running on the result

- No `packaging_size` should equal a number that appears in the name next to a
  weight unit — that means a piece size leaked into the count column.
- Any `brand` that matches an entity in the `entities` table is probably a
  customer, not a manufacturer.
- Two rows sharing `item_name` + `brand` + `variety` + packaging will violate
  `inventory_unique_identity`. Since names are already distinct and this process
  only adds columns, this cannot trigger — but it can once names are eventually
  shortened.

---

## 7. Still open

- **`item_name` shortening** is deliberately not done, and must not be done
  until `LocalItemMatcher` reads these columns. Doing it first makes matching
  worse.
- **`aliases`** is unpopulated. It is the natural home for the spellings
  customers actually use (`مياه` for `مياة`, `نسكافيه` for `نسكافي`), and would
  help matching more than anything else here.
