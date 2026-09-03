// Runs the local matcher against real data and prints what it got right.
//
//   dart run tool/match_report.dart
//
// Reads:
//   tool/fixtures/inventory.csv   name,unit,category,sku,brand,variety,
//                                 packaging_size,packaging_size_unit,aliases
//                                 (header optional; everything after sku is
//                                 optional, and aliases are "/"-separated)
//   tool/fixtures/messages/*.txt  one real request per file
//
// No Flutter, no Firebase, no network, no API key, no cost. That is the whole
// point: match quality can now be iterated on in a one-second loop instead of a
// sixty-second one, and tuning it does not spend quota.
import 'dart:io';

import 'package:ura_core/features/verifier/data/local_item_matcher.dart';
import 'package:ura_core/shared/models/inventory_item.dart';

/// Above this, the row is treated as settled. Tune once there is real data —
/// finding the right value is a large part of what this report is for.
const confidentAt = 0.60;

/// Below this the line is treated as unmatched rather than offered as a guess.
///
/// Low on purpose. Rejecting a line is now the content-word rule's job, not a
/// score threshold's: a row that shares no product word never becomes a
/// candidate at all. A brand on its own — "باجة" — genuinely scores low
/// because it does not say which باجة, and that is a choice to offer, not a
/// miss to report.
const hopelessBelow = 0.15;

/// A win has to be a clear win. "شاي اخضر" fits three rows — احمد, الربيع and
/// توينجز — and the only reason توينجز edges ahead is that its name is shorter,
/// so a larger share of it got matched. That is an artefact of how coverage is
/// measured, not evidence about what the sender meant. Unless the best
/// candidate beats the runner-up by this much, it is a choice, not an answer.
const marginAt = 0.15;

void main(List<String> args) {
  final inventoryFile = File('tool/fixtures/inventory.csv');
  final messageDir = Directory('tool/fixtures/messages');

  if (!inventoryFile.existsSync()) {
    stderr.writeln('''
Missing tool/fixtures/inventory.csv

Export the inventory and save it there as:

  name,unit,category,sku
  مياه نوفا 330 مل,كرتونة,مشروبات,NOVA330

The header line is optional, and only the first column is required.''');
    exit(1);
  }

  final inventory = _readInventory(inventoryFile);
  _checkEncoding(inventory);
  final matcher = LocalItemMatcher(inventory);
  stdout.writeln('Catalog: ${inventory.length} rows\n');

  if (!messageDir.existsSync()) {
    stderr.writeln('Missing tool/fixtures/messages/ — drop real .txt requests in there.');
    exit(1);
  }

  final messages = messageDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (messages.isEmpty) {
    stderr.writeln('No .txt files in tool/fixtures/messages/');
    exit(1);
  }

  var confident = 0, ambiguous = 0, missed = 0, noise = 0;

  for (final file in messages) {
    stdout.writeln('━' * 72);
    stdout.writeln(file.uri.pathSegments.last);
    stdout.writeln('━' * 72);

    for (final line in matcher.match(file.readAsStringSync())) {
      if (line.isNoise) {
        noise++;
        stdout.writeln('  ·  ${_clip(line.text)}');
        continue;
      }

      final best = line.best;
      if (best == null || best.score < hopelessBelow) {
        missed++;
        stdout.writeln('  ✗  ${_clip(line.text)}');
        stdout.writeln('       nothing in the catalog');
        continue;
      }

      final qty = line.quantity == line.quantity.roundToDouble()
          ? line.quantity.toInt().toString()
          : line.quantity.toString();

      final runnerUp = line.candidates.length > 1 ? line.candidates[1].score : 0.0;
      if (best.score >= confidentAt && best.score - runnerUp >= marginAt) {
        confident++;
        stdout.writeln('  ✓  ${_clip(line.text)}');
        stdout.writeln('       $qty × ${best.item.itemName}  '
            '[${best.score.toStringAsFixed(2)}]');
      } else {
        ambiguous++;
        stdout.writeln('  ?  ${_clip(line.text)}   (qty $qty)');
        for (final c in line.candidates.take(4)) {
          stdout.writeln('       ${c.score.toStringAsFixed(2)}  ${c.item.itemName}');
        }
      }
    }
    stdout.writeln();
  }

  final decided = confident + ambiguous + missed;
  stdout.writeln('━' * 72);
  stdout.writeln('${messages.length} messages, $decided request lines '
      '($noise noise lines ignored)\n');
  _bar('settled locally', confident, decided);
  _bar('needs a choice ', ambiguous, decided);
  _bar('no match       ', missed, decided);
  stdout.writeln('''
\nRead "settled locally" as the share that would never touch the model.
"needs a choice" and "no match" are what a model would still be asked about —
and they go out as a handful of candidate rows, not the whole catalog.''');
}

void _bar(String label, int n, int total) {
  if (total == 0) return;
  final pct = 100 * n / total;
  final filled = (pct / 2.5).round();
  stdout.writeln('  $label  ${'█' * filled}${'░' * (40 - filled)} '
      '${pct.toStringAsFixed(0).padLeft(3)}%  ($n)');
}

String _clip(String s) => s.length <= 58 ? s : '${s.substring(0, 57)}…';

/// Excel on Windows saves CSV as Windows-1256 unless you pick "CSV UTF-8", and
/// the Arabic comes back as mojibake. Every match then fails, the report reads
/// 0% and the matcher looks broken when the file is what's wrong. Cheaper to
/// say so than to let anyone debug that.
void _checkEncoding(List<InventoryItem> inventory) {
  if (inventory.isEmpty) return;
  final arabic = RegExp('[ء-ي]');
  final withArabic = inventory.where((i) => arabic.hasMatch(i.itemName)).length;
  if (withArabic > inventory.length * 0.2) return;

  stderr.writeln('''
⚠  Only $withArabic of ${inventory.length} rows contain Arabic letters.

   That almost always means inventory.csv is not UTF-8. In Excel use
   "Save As → CSV UTF-8 (Comma delimited)", not plain "CSV".

   First row read as: ${inventory.first.itemName}
''');
}

List<InventoryItem> _readInventory(File file) {
  final List<String> lines;
  try {
    lines = file.readAsLinesSync();
  } on FileSystemException {
    // Windows-1256 bytes are not valid UTF-8, so the read throws outright
    // rather than producing wrong text. Same cause as _checkEncoding, caught
    // earlier and louder.
    stderr.writeln('''
✗  ${file.path} is not UTF-8, so it can't be read.

   In Excel: "Save As → CSV UTF-8 (Comma delimited)", not plain "CSV".
   Plain CSV on Windows writes Windows-1256 and mangles Arabic.''');
    exit(1);
  }

  final rows = <InventoryItem>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final cells = line.split(RegExp('[,\t;]')).map((c) => c.trim()).toList();
    final name = cells.first;
    if (name.isEmpty) continue;
    // Skip a header row without needing to be told there is one.
    if (rows.isEmpty && name.toLowerCase() == 'name') continue;

    String? at(int i) {
      if (i >= cells.length) return null;
      final cell = cells[i];
      // Supabase exports SQL NULL as the four letters "null". Left alone it
      // becomes a word on every row and pollutes the index.
      if (cell.isEmpty || cell.toLowerCase() == 'null') return null;
      return cell;
    }

    // Columns 4 onward are optional, so an older four-column fixture still
    // loads -- it just reports what the matcher could do before the 2026-09-02
    // backfill, which is exactly the comparison this tool is for.
    final packaging = at(6);
    final aliases = at(8);
    rows.add(InventoryItem(
      id: 'row-${rows.length + 1}',
      itemName: name,
      unit: at(1) ?? 'قطعة',
      category: at(2),
      sku: at(3),
      brand: at(4),
      variety: at(5),
      packagingSize: packaging == null ? null : double.tryParse(packaging),
      packagingSizeUnit: at(7),
      aliases: aliases?.split('/').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
      quantity: 0,
    ));
  }
  return rows;
}
