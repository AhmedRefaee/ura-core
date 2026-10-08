# Match-report fixtures

Real inventory and real customer messages go here. **Both are gitignored** —
they are business data, and a forwarded WhatsApp message usually has a person's
name and phone number in it.

Run the report with:

```
dart run tool/match_report.dart
```

No Flutter, no Firebase, no network, no API key, no cost. Tuning the matcher is
a one-second loop that spends nothing.

## `inventory.csv`

One row per item. Only the first column is required; the header line is
optional. Comma, tab or semicolon separated.

```
name,unit,category,sku
مياه نوفا 330 مل,كرتونة,مشروبات,NOVA330
مياه نوفا 500 مل,كرتونة,مشروبات,NOVA500
صابون لوكس,علبة,منظفات,LUX1
```

Category and SKU are optional but worth including — both feed the ranking, and
SKU in particular is highly distinctive when a sender happens to quote one.

## `messages/*.txt`

One real request per file. **Keep the mess.** The greetings, the inconsistent
spelling, the mixed Arabic-Indic and Western digits, the numbering that isn't a
quantity — that is the actual test. A cleaned-up message proves nothing.

Anonymise names and phone numbers if you like; replace them with other names and
numbers rather than deleting the lines, so the noise detection is still exercised.

```
السلام عليكم ورحمة الله
معاك احمد من فرع المعادي
محتاج لو سمحت:
1. ٥ كرتونة مياه نوفا ٣٣٠
2. 3 علبة صابون لوكس
- مياه
وشكرا جزيلا
01001234567
```

## Reading the output

- `✓` settled locally — would never reach the model
- `?` needs a choice — several plausible rows, ranked
- `✗` no match — nothing in the catalog scored
- `·` noise — no catalog word at all, so a greeting or a sign-off

The two thresholds are constants at the top of `tool/match_report.dart`.
Finding the right values against real data is most of what this report is for.
