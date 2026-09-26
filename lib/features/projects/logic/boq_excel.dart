import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../../../core/text/arabic_text.dart';
import '../../../shared/models/project_item.dart';

/// VAT on quotations. Prices are always stored pre-VAT; VAT is derived.
const kVatRate = 0.15;

/// Subtotal / VAT / total for one جدول الكميات, in the same rounding the
/// paper quotations use (VAT rounded to the halala).
class BoqTotals {
  final double subtotal;
  final double vat;
  final double total;
  const BoqTotals(this.subtotal, this.vat, this.total);

  factory BoqTotals.of(Iterable<ProjectItem> items) {
    // Integer halalas: 533,870.70 * 0.15 must give 80,080.61, and doubles
    // land on 80,080.6049... and round down.
    final cents = items.fold<int>(0, (sum, i) => sum + ((i.totalPrice ?? 0) * 100).round());
    final vatCents = (cents * (kVatRate * 100).round() + 50) ~/ 100;
    return BoqTotals(cents / 100, vatCents / 100, (cents + vatCents) / 100);
  }
}

class BoqCategory {
  final String name;
  final List<ProjectItem> items;
  const BoqCategory(this.name, this.items);

  BoqTotals get totals => BoqTotals.of(items);
  bool get hasPrices => items.any((i) => i.totalPrice != null);
}

/// Groups items into their tables, keeping the order each category first
/// appears in (which is sort_order order).
List<BoqCategory> groupByCategory(List<ProjectItem> items) {
  final groups = <String, List<ProjectItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.category.trim(), () => []).add(item);
  }
  return [for (final e in groups.entries) BoqCategory(e.key, e.value)];
}

String categoryTitle(String category) =>
    category.trim().isEmpty ? 'جدول الكميات' : 'جدول الكميات : ${category.trim()}';

// ── Export ────────────────────────────────────────────────────────────────────

const _headers = ['م', 'البند', 'وصف البند', 'الكمية', 'الوحدة', 'السعر الإفرادي', 'السعر الإجمالي'];

Uint8List buildBoqWorkbook({
  required String projectName,
  required String entityName,
  required List<ProjectItem> items,
}) {
  final excel = Excel.createExcel();
  const sheetName = 'بنود العقد';
  excel.rename('Sheet1', sheetName);
  final sheet = excel[sheetName];

  final thin = Border(borderStyle: BorderStyle.Thin);
  CellStyle style({bool bold = false, bool grey = false, bool money = false, HorizontalAlign? align}) => CellStyle(
        bold: bold,
        backgroundColorHex: grey ? ExcelColor.grey300 : ExcelColor.none,
        horizontalAlign: align ?? HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thin,
        rightBorder: thin,
        topBorder: thin,
        bottomBorder: thin,
        numberFormat: money ? NumFormat.standard_4 : NumFormat.standard_0,
      );

  void put(int row, int col, CellValue value, CellStyle s) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = value;
    cell.cellStyle = s;
  }

  var row = 0;
  final title = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
  title.value = TextCellValue('$entityName — $projectName');
  title.cellStyle = CellStyle(bold: true, fontSize: 14);
  row += 2;

  for (final category in groupByCategory(items)) {
    final heading = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    heading.value = TextCellValue(categoryTitle(category.name));
    heading.cellStyle = CellStyle(bold: true, fontSize: 12);
    row++;

    for (var c = 0; c < _headers.length; c++) {
      put(row, c, TextCellValue(_headers[c]), style(bold: true, grey: true));
    }
    row++;

    for (var i = 0; i < category.items.length; i++) {
      final item = category.items[i];
      put(row, 0, IntCellValue(i + 1), style());
      put(row, 1, TextCellValue(item.itemName), style(align: HorizontalAlign.Right));
      put(row, 2, TextCellValue(item.description ?? ''), style(align: HorizontalAlign.Right));
      put(row, 3, DoubleCellValue(item.quantity), style(money: true));
      put(row, 4, TextCellValue(item.unit), style());
      if (item.unitPrice != null) put(row, 5, DoubleCellValue(item.unitPrice!), style(money: true));
      if (item.totalPrice != null) put(row, 6, DoubleCellValue(item.totalPrice!), style(money: true));
      row++;
    }

    final t = category.totals;
    for (final (label, value) in [
      if (category.hasPrices) ...[
        ('الإجمالي غير شامل ضريبة القيمة المضافة', t.subtotal),
        ('قيمة الضريبة المضافة ${(kVatRate * 100).round()}%', t.vat),
        ('الإجمالي شامل ضريبة القيمة المضافة', t.total),
      ],
    ]) {
      put(row, 1, TextCellValue(label), style(bold: true, grey: true, align: HorizontalAlign.Right));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
      );
      put(row, 6, DoubleCellValue(value), style(bold: true, grey: true, money: true));
      row++;
    }
    row++;
  }

  const widths = [6.0, 24.0, 44.0, 12.0, 10.0, 14.0, 16.0];
  for (var c = 0; c < widths.length; c++) {
    sheet.setColumnWidth(c, widths[c]);
  }

  // excel 4.0.6 only writes rightToLeft for a sheet that already exists in the
  // file's XML, which a sheet created in this session doesn't. One
  // encode → decode round trip makes it exist; then RTL sticks.
  final reopened = Excel.decodeBytes(excel.encode()!);
  reopened[sheetName].isRTL = true;
  return Uint8List.fromList(reopened.encode()!);
}

// ── Import ────────────────────────────────────────────────────────────────────

class BoqRowError {
  final String sheet;
  final int rowNumber;
  final List<String> errors;
  final String preview;
  const BoqRowError({required this.sheet, required this.rowNumber, required this.errors, required this.preview});
}

class BoqParseResult {
  /// In file order, with category set; sortOrder is their position.
  final List<ProjectItem> items;
  final List<BoqRowError> errors;

  /// True when no header row (one containing "البند") was found anywhere --
  /// almost certainly not a quotation file.
  final bool noHeaderFound;

  const BoqParseResult({required this.items, required this.errors, required this.noHeaderFound});

  List<BoqCategory> get categories => groupByCategory(items);
  bool get canImport => items.isNotEmpty && errors.isEmpty;
}

enum _Col { number, name, description, quantity, unit, unitPrice, total }

/// Reads a quotation workbook: ours, or Ahmed's own files. Every sheet, every
/// row, with columns found by header text rather than position, since the
/// real files don't put them where our export does.
BoqParseResult parseBoqWorkbook(Uint8List bytes, {String projectId = ''}) {
  final excel = Excel.decodeBytes(bytes);
  final items = <ProjectItem>[];
  final errors = <BoqRowError>[];
  var sawHeader = false;
  final multiSheet = excel.tables.length > 1;

  for (final entry in excel.tables.entries) {
    final sheetName = entry.key;
    var category = multiSheet ? sheetName.trim() : '';
    Map<_Col, int>? columns;

    final rows = entry.value.rows;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final texts = [for (final cell in row) _text(cell?.value)];
      final folded = [for (final t in texts) ArabicText.normalize(t)];

      final titleIdx = folded.indexWhere((f) => f.startsWith('جدول الكميات'));
      if (titleIdx >= 0) {
        final raw = texts[titleIdx];
        final colon = raw.indexOf(':');
        category = colon >= 0 ? raw.substring(colon + 1).trim() : '';
        columns = null;
        continue;
      }

      if (folded.any((f) => f == 'البند')) {
        columns = _mapHeader(folded);
        sawHeader = true;
        continue;
      }

      final cols = columns;
      if (cols == null) continue;
      if (folded.any((f) => f.startsWith('الاجمالي') || f.contains('ضريبه'))) continue;

      String cellText(_Col c) => cols[c] == null || cols[c]! >= texts.length ? '' : texts[cols[c]!];
      CellValue? cellValue(_Col c) => cols[c] == null || cols[c]! >= row.length ? null : row[cols[c]!]?.value;

      final name = cellText(_Col.name);
      final description = cellText(_Col.description);
      final unit = cellText(_Col.unit);
      final qtyRaw = cellValue(_Col.quantity);
      final priceRaw = cellValue(_Col.unitPrice);
      final totalRaw = cellValue(_Col.total);

      // Blank template rows (only a م number) aren't items.
      if ([name, description, unit, _text(qtyRaw), _text(priceRaw), _text(totalRaw)].every((s) => s.isEmpty)) {
        continue;
      }

      final rowErrors = <String>[];
      if (name.isEmpty) rowErrors.add('اسم البند مفقود');
      if (unit.isEmpty) rowErrors.add('الوحدة مفقودة');
      final qty = _number(qtyRaw);
      if (_text(qtyRaw).isEmpty) {
        rowErrors.add('الكمية مفقودة');
      } else if (qty == null) {
        rowErrors.add('الكمية ليست رقماً: ${_text(qtyRaw)}');
      } else if (qty < 0) {
        rowErrors.add('الكمية سالبة');
      }
      final unitPrice = _number(priceRaw);
      if (unitPrice == null && _text(priceRaw).isNotEmpty && priceRaw is! FormulaCellValue) {
        rowErrors.add('السعر الإفرادي ليس رقماً: ${_text(priceRaw)}');
      }
      var total = _number(totalRaw);
      if (total == null && _text(totalRaw).isNotEmpty && totalRaw is! FormulaCellValue) {
        rowErrors.add('السعر الإجمالي ليس رقماً: ${_text(totalRaw)}');
      }

      if (rowErrors.isNotEmpty) {
        errors.add(BoqRowError(
          sheet: sheetName,
          rowNumber: r + 1,
          errors: rowErrors,
          preview: [name, description].where((s) => s.isNotEmpty).join(' - '),
        ));
        continue;
      }

      // A formula total (=D5*F5) has no cached value once parsed; recompute.
      total ??= unitPrice == null ? null : ((qty! * unitPrice) * 100).round() / 100;
      items.add(ProjectItem(
        id: '',
        projectId: projectId,
        category: category,
        sortOrder: items.length + 1,
        itemName: name,
        description: description.isEmpty ? null : description,
        quantity: qty!,
        unit: unit,
        unitPrice: unitPrice,
        totalPrice: total,
      ));
    }
  }

  return BoqParseResult(items: items, errors: errors, noHeaderFound: !sawHeader);
}

Map<_Col, int> _mapHeader(List<String> folded) {
  final map = <_Col, int>{};
  for (var c = 0; c < folded.length; c++) {
    final f = folded[c];
    if (f.isEmpty) continue;
    final col = switch (f) {
      'م' => _Col.number,
      'البند' => _Col.name,
      _ when f.contains('وصف') => _Col.description,
      _ when f.contains('كميه') => _Col.quantity,
      _ when f.contains('وحده') => _Col.unit,
      _ when f.contains('افرادي') => _Col.unitPrice,
      _ when f.contains('اجمالي') => _Col.total,
      _ => null,
    };
    if (col != null) map.putIfAbsent(col, () => c);
  }
  return map;
}

String _text(CellValue? v) => switch (v) {
      null => '',
      FormulaCellValue() => '',
      _ => v.toString().trim(),
    };

/// Numeric cells as-is. Text cells as written in Arabic spreadsheets: Arabic
/// digits allowed, "," and "٬" are thousands separators (50,700.00), "٫" is
/// the decimal point.
double? _number(CellValue? v) {
  switch (v) {
    case IntCellValue(:final value):
      return value.toDouble();
    case DoubleCellValue(:final value):
      return value;
    case null || FormulaCellValue():
      return null;
    default:
      final buf = StringBuffer();
      for (final rune in v.toString().trim().runes) {
        if (rune >= 0x0660 && rune <= 0x0669) {
          buf.write(rune - 0x0660);
        } else if (rune >= 0x06F0 && rune <= 0x06F9) {
          buf.write(rune - 0x06F0);
        } else {
          final ch = String.fromCharCode(rune);
          if (ch == '٫') {
            buf.write('.');
          } else if ('0123456789.-'.contains(ch)) {
            buf.write(ch);
          }
        }
      }
      final s = buf.toString();
      return s.isEmpty ? null : double.tryParse(s);
  }
}
