// Runs the local matcher against real data and prints what it got right.
//
//   dart run tool/match_report.dart
//
// Reads:
//   tool/fixtures/inventory.csv   name,unit,category,sku  (header optional)
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
const hopelessBelow = 0.30;

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

      if (best.score >= confidentAt) {
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

List<InventoryItem> _readInventory(File file) {
  final rows = <InventoryItem>[];
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final cells = line.split(RegExp('[,\t;]')).map((c) => c.trim()).toList();
    final name = cells.first;
    if (name.isEmpty) continue;
    // Skip a header row without needing to be told there is one.
    if (rows.isEmpty && name.toLowerCase() == 'name') continue;

    String? at(int i) {
      if (i >= cells.length) return null;
      return cells[i].isEmpty ? null : cells[i];
    }

    rows.add(InventoryItem(
      id: 'row-${rows.length + 1}',
      itemName: name,
      unit: at(1) ?? 'قطعة',
      category: at(2),
      sku: at(3),
      quantity: 0,
    ));
  }
  return rows;
}
