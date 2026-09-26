import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import '../../../core/text/arabic_text.dart';
import '../../../shared/models/project_item.dart';

/// VAT on quotations. Prices are always stored pre-VAT; VAT is derived.
const kVatRate = 0.15;

double _round2(double v) => (v * 100).round() / 100;

/// Subtotal / VAT / total, VAT rounded to the halala like the paper
/// quotations.
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

/// Groups items by category, in the order each category first appears.
List<BoqCategory> groupByCategory(List<ProjectItem> items) {
  final groups = <String, List<ProjectItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.category.trim(), () => []).add(item);
  }
  return [for (final e in groups.entries) BoqCategory(e.key, e.value)];
}

// ── Export: one flat table, one row per item ─────────────────────────────────

const boqHeaders = [
  'الفئة',
  'البند',
  'وصف البند',
  'الكمية',
  'الوحدة',
  'سعر الوحدة',
  'سعر الوحدة شامل الضريبة',
  'الإجمالي',
  'الإجمالي شامل الضريبة',
];

/// Blank, formula-ready rows added after the items so lines can be added in
/// Excel without copying formatting.
const _spareRows = 100;

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
  CellStyle style({bool bold = false, bool grey = false, bool money = false, bool right = false}) => CellStyle(
        bold: bold,
        backgroundColorHex: grey ? ExcelColor.grey300 : ExcelColor.none,
        horizontalAlign: right ? HorizontalAlign.Right : HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: thin,
        rightBorder: thin,
        topBorder: thin,
        bottomBorder: thin,
        numberFormat: money ? NumFormat.standard_4 : NumFormat.standard_0,
      );

  void put(int row, int col, CellValue? value, CellStyle s) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    if (value != null) cell.value = value;
    cell.cellStyle = s;
  }

  final title = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
  title.value = TextCellValue('$entityName — $projectName');
  title.cellStyle = CellStyle(bold: true, fontSize: 14);
  final hint = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
  hint.value = TextCellValue(
      'املأ: الفئة، البند، الوصف، الكمية، الوحدة، سعر الوحدة (قبل الضريبة). الأعمدة الرمادية تُحسب تلقائياً (ضريبة ${(kVatRate * 100).round()}%).');
  hint.cellStyle = CellStyle(italic: true, fontColorHex: ExcelColor.grey);

  const headerRow = 2;
  for (var c = 0; c < boqHeaders.length; c++) {
    put(headerRow, c, TextCellValue(boqHeaders[c]), style(bold: true, grey: true));
  }

  final vat = 1 + kVatRate;
  final lastRow = headerRow + items.length + _spareRows;
  for (var r = headerRow + 1; r <= lastRow; r++) {
    final i = r - headerRow - 1;
    final item = i < items.length ? items[i] : null;
    final x = r + 1; // Excel row numbers are 1-based
    put(r, 0, item == null ? null : TextCellValue(item.category), style(right: true));
    put(r, 1, item == null ? null : TextCellValue(item.itemName), style(right: true));
    put(r, 2, item == null ? null : TextCellValue(item.description ?? ''), style(right: true));
    put(r, 3, item == null ? null : DoubleCellValue(item.quantity), style(money: true));
    put(r, 4, item == null ? null : TextCellValue(item.unit), style());
    put(r, 5, item?.unitPrice == null ? null : DoubleCellValue(item!.unitPrice!), style(money: true));
    // Derived columns are formulas, so editing a quantity or price in Excel
    // keeps them right. The importer ignores formula cells and recomputes.
    put(r, 6, FormulaCellValue('IF(F$x="","",ROUND(F$x*$vat,2))'), style(grey: true, money: true));
    put(r, 7, FormulaCellValue('IF(OR(D$x="",F$x=""),"",ROUND(D$x*F$x,2))'), style(grey: true, money: true));
    put(r, 8, FormulaCellValue('IF(H$x="","",ROUND(H$x*$vat,2))'), style(grey: true, money: true));
  }

  const widths = [18.0, 26.0, 48.0, 11.0, 10.0, 12.0, 14.0, 14.0, 16.0];
  for (var c = 0; c < widths.length; c++) {
    sheet.setColumnWidth(c, widths[c]);
  }

  // excel 4.0.6 only writes rightToLeft for a sheet that already exists in
  // the file's XML, which a sheet created in this session doesn't. One
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

enum _Col { number, category, name, description, quantity, unit, unitPrice, unitPriceVat, total, totalVat }

/// Reads a quotation workbook: our export, or a hand-made one. Every sheet,
/// every row; columns are found by header text, not position. Handles both
/// layouts seen in real files: a category column on each row (الفئة /
/// الحزمة), and stacked "جدول الكميات : <فئة>" tables with totals rows.
BoqParseResult parseBoqWorkbook(Uint8List bytes, {String projectId = ''}) {
  final excel = Excel.decodeBytes(sanitizeXlsx(bytes));
  final items = <ProjectItem>[];
  final errors = <BoqRowError>[];
  var sawHeader = false;
  final multiSheet = excel.tables.length > 1;

  for (final entry in excel.tables.entries) {
    final sheetName = entry.key;
    var tableCategory = multiSheet ? sheetName.trim() : '';
    Map<_Col, int>? columns;

    final rows = entry.value.rows;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final texts = [for (final cell in row) _clean(_text(cell?.value))];
      final folded = [for (final t in texts) ArabicText.normalize(t)];

      final titleIdx = folded.indexWhere((f) => f.startsWith('جدول الكميات'));
      if (titleIdx >= 0) {
        final raw = texts[titleIdx];
        final colon = raw.indexOf(':');
        tableCategory = colon >= 0 ? raw.substring(colon + 1).trim() : '';
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
      final rowCategory = cellText(_Col.category);
      final qtyRaw = cellValue(_Col.quantity);
      final priceRaw = cellValue(_Col.unitPrice);
      final priceVatRaw = cellValue(_Col.unitPriceVat);
      final totalRaw = cellValue(_Col.total);
      final totalVatRaw = cellValue(_Col.totalVat);

      // Spare rows (formulas only, or just a م number) aren't items.
      if ([name, description, unit, _text(qtyRaw), _text(priceRaw), _text(priceVatRaw), _text(totalRaw)]
          .every((s) => s.isEmpty)) {
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
      double? numberOrError(CellValue? raw, String label) {
        final n = _number(raw);
        if (n == null && _text(raw).isNotEmpty) rowErrors.add('$label ليس رقماً: ${_text(raw)}');
        return n;
      }

      var unitPrice = numberOrError(priceRaw, 'سعر الوحدة');
      final unitPriceVat = numberOrError(priceVatRaw, 'سعر الوحدة شامل الضريبة');
      var total = numberOrError(totalRaw, 'الإجمالي');
      final totalVat = numberOrError(totalVatRaw, 'الإجمالي شامل الضريبة');

      if (rowErrors.isNotEmpty) {
        errors.add(BoqRowError(
          sheet: sheetName,
          rowNumber: r + 1,
          errors: rowErrors,
          preview: [name, description].where((s) => s.isNotEmpty).join(' - '),
        ));
        continue;
      }

      // Stored prices are pre-VAT; a VAT-inclusive figure is only used when
      // the pre-VAT one wasn't given.
      unitPrice ??= unitPriceVat == null ? null : _round2(unitPriceVat / (1 + kVatRate));
      total ??= totalVat == null ? null : _round2(totalVat / (1 + kVatRate));
      total ??= unitPrice == null ? null : _round2(qty! * unitPrice);

      items.add(ProjectItem(
        id: '',
        projectId: projectId,
        category: rowCategory.isNotEmpty ? rowCategory : tableCategory,
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
    final vatIncluded = f.contains('شامل') || f.contains('ضريبه');
    final col = switch (f) {
      'م' => _Col.number,
      'البند' => _Col.name,
      _ when f.contains('اسم الصنف') => _Col.name,
      _ when f.contains('حزمه') || f.contains('الفيه') || f == 'فيه' || f.contains('تصنيف') => _Col.category,
      _ when f.contains('وصف') => _Col.description,
      _ when f.contains('كميه') => _Col.quantity,
      _ when vatIncluded && f.contains('اجمالي') => _Col.totalVat,
      _ when vatIncluded => _Col.unitPriceVat,
      _ when f.contains('اجمالي') => _Col.total,
      _ when f.contains('افرادي') || (f.contains('سعر') && f.contains('وحده')) => _Col.unitPrice,
      _ when f.contains('وحده') => _Col.unit,
      _ => null,
    };
    if (col != null) map.putIfAbsent(col, () => c);
  }
  return map;
}

/// Persian-keyboard letters that show up in Arabic spreadsheets (e.g. text
/// pasted from PDFs: "الكمیة", "مشتقاتھ"). ArabicText treats them as
/// separators, so they're folded to their Arabic forms first.
String _clean(String s) => s
    .replaceAll('ی', 'ي')
    .replaceAll('ک', 'ك')
    .replaceAll('ھ', 'ه')
    .replaceAll('ە', 'ه')
    .trim();

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

// ── Workaround for files saved by Microsoft Excel ────────────────────────────

/// Built-in number-format ids that excel 4.0.6 knows about. Anything else
/// below 164 makes its parser throw ("custom numFmtId starts at 164") or
/// trip an assert in debug builds -- and Excel writes such ids (41-44, the
/// accounting formats) into nearly every file it saves.
const _knownBuiltinNumFmts = {
  0, 1, 2, 3, 4, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, //
  37, 38, 39, 40, 45, 46, 47, 48, 49,
};

/// Rewrites the parts of an .xlsx the excel package chokes on, leaving cell
/// values untouched. Returns the input unchanged when nothing needs fixing
/// or it isn't a zip.
///
/// * xl/styles.xml -- custom number formats declared with ids < 164 are
///   renumbered to free ids ≥ 164 (definitions and references together);
///   references to built-in ids the package doesn't know fall back to
///   General (0). Only how numbers are displayed changes.
/// * xl/_rels/workbook.xml.rels -- absolute targets ("/xl/worksheets/…",
///   written by LibreOffice/openpyxl and others) become relative, since the
///   package blindly prefixes "xl/" and then can't find the sheet.
Uint8List sanitizeXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return bytes;
  }

  final patched = <String, String>{};
  final styles = archive.findFile('xl/styles.xml');
  if (styles != null) {
    final xml = utf8.decode(styles.content as List<int>);
    final fixed = _fixNumFmts(xml);
    if (fixed != xml) patched[styles.name] = fixed;
  }
  final rels = archive.findFile('xl/_rels/workbook.xml.rels');
  if (rels != null) {
    final xml = utf8.decode(rels.content as List<int>);
    final fixed = xml.replaceAll('Target="/xl/', 'Target="');
    if (fixed != xml) patched[rels.name] = fixed;
  }
  if (patched.isEmpty) return bytes;

  final out = Archive();
  for (final file in archive.files) {
    final text = patched[file.name];
    if (text == null) {
      out.addFile(file);
    } else {
      final data = utf8.encode(text);
      out.addFile(ArchiveFile(file.name, data.length, data));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

String _fixNumFmts(String xml) {
  final defined = {
    for (final m in RegExp(r'<numFmt\b[^>]*?\bnumFmtId="(\d+)"').allMatches(xml)) int.parse(m[1]!),
  };
  var next = math.max(163, defined.fold<int>(0, math.max)) + 1;
  final remap = {for (final id in defined.where((id) => id < 164)) id: next++};

  return xml.replaceAllMapped(RegExp(r'numFmtId="(\d+)"'), (m) {
    final id = int.parse(m[1]!);
    final moved = remap[id];
    if (moved != null) return 'numFmtId="$moved"';
    if (id < 164 && !defined.contains(id) && !_knownBuiltinNumFmts.contains(id)) return 'numFmtId="0"';
    return m[0]!;
  });
}
