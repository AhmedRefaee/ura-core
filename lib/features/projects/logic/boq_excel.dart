import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import '../../../core/text/arabic_text.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';

/// VAT on quotations. Prices are always stored pre-VAT; VAT is derived.
const kVatRate = 0.15;

class BoqCategory {
  final String name;
  final List<ProjectItem> items;
  const BoqCategory(this.name, this.items);
}

/// Groups items by category, in the order each category first appears.
List<BoqCategory> groupByCategory(List<ProjectItem> items) {
  final groups = <String, List<ProjectItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.category.trim(), () => []).add(item);
  }
  return [for (final e in groups.entries) BoqCategory(e.key, e.value)];
}

/// Folds text for searching quotation lines: Arabic spelling variants
/// (أ/إ/ا, ة/ه, ى/ي, tashkeel) and Persian-keyboard letters compare equal.
String foldForSearch(String s) => ArabicText.normalize(_clean(s));

/// Everything a person might search a line by, folded once.
String boqSearchKey(ProjectItem i) =>
    foldForSearch('${i.itemName} ${i.description ?? ''} ${i.category} ${i.unit}');

// ── Files: the template adds lines, the exported file updates them ───────────

/// The table's columns, in the same order as the Excel files.
const boqHeaders = [
  'م',
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

/// As [boqHeaders], with the two required columns starred as in the inventory
/// templates. These exact texts are how an upload is recognised as our file.
const _fileHeaders = [
  'م',
  'الفئة',
  'البند *',
  'وصف البند',
  'الكمية',
  'الوحدة *',
  'سعر الوحدة',
  'سعر الوحدة شامل الضريبة',
  'الإجمالي',
  'الإجمالي شامل الضريبة',
];

/// Only the file that updates existing lines has this column.
const _idHeader = 'الرقم التعريفي (لا تعدل)';

/// Blank, formula-ready rows in the template, so lines can be added in Excel
/// without copying formatting.
const _spareRows = 500;

const _headerRow = 2;

/// The file for adding new lines. Numbering starts at [firstNumber], so it
/// carries on after the lines the project already has.
Uint8List buildBoqTemplate({
  required String projectName,
  required String entityName,
  int firstNumber = 1,
}) => _buildWorkbook(
  projectName: projectName,
  entityName: entityName,
  hint:
      'الإلزامي: البند والوحدة فقط، وباقي الحقول اختيارية. الترقيم تلقائي والأعمدة الرمادية تُحسب تلقائياً (ضريبة ${(kVatRate * 100).round()}%).',
  items: const [],
  spareRows: _spareRows,
  firstNumber: firstNumber,
);

/// The file for updating the project's current lines, matched by id on upload.
Uint8List buildBoqUpdateFile({
  required String projectName,
  required String entityName,
  required List<ProjectItem> items,
}) => _buildWorkbook(
  projectName: projectName,
  entityName: entityName,
  hint:
      'عدّل ما تريد ثم ارفع الملف. لا تعدّل عمود الرقم التعريفي. حذف صف من الملف لا يحذف البند. الأعمدة الرمادية تُحسب تلقائياً (ضريبة ${(kVatRate * 100).round()}%).',
  items: items,
  spareRows: 0,
  firstNumber: 1,
  withIds: true,
);

Uint8List _buildWorkbook({
  required String projectName,
  required String entityName,
  required String hint,
  required List<ProjectItem> items,
  required int spareRows,
  required int firstNumber,
  bool withIds = false,
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
  final hintCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
  hintCell.value = TextCellValue(hint);
  hintCell.cellStyle = CellStyle(italic: true, fontColorHex: ExcelColor.grey);

  final headers = [..._fileHeaders, if (withIds) _idHeader];
  for (var c = 0; c < headers.length; c++) {
    put(_headerRow, c, TextCellValue(headers[c]), style(bold: true, grey: true));
  }

  final vat = 1 + kVatRate;
  final lastRow = _headerRow + items.length + spareRows;
  for (var r = _headerRow + 1; r <= lastRow; r++) {
    final i = r - _headerRow - 1;
    final item = i < items.length ? items[i] : null;
    final x = r + 1; // Excel row numbers are 1-based
    // A spare row numbers itself once a name is typed in it. The importer
    // never reads this column: a line's number is its position in the project.
    put(
      r,
      0,
      item != null
          ? IntCellValue(i + 1)
          : FormulaCellValue('IF(C$x="","",ROW()-${_headerRow + 1}+${firstNumber - 1})'),
      style(grey: true),
    );
    put(r, 1, item == null ? null : TextCellValue(item.category), style(right: true));
    put(r, 2, item == null ? null : TextCellValue(item.itemName), style(right: true));
    put(r, 3, item?.description == null ? null : TextCellValue(item!.description!), style(right: true));
    put(r, 4, item == null || item.quantity == 0 ? null : DoubleCellValue(item.quantity), style(money: true));
    put(r, 5, item == null ? null : TextCellValue(item.unit), style());
    put(r, 6, item?.unitPrice == null ? null : DoubleCellValue(item!.unitPrice!), style(money: true));
    // Derived columns are formulas, so editing a quantity or price in Excel
    // keeps them right. The importer ignores them and recomputes.
    put(r, 7, FormulaCellValue('IF(G$x="","",ROUND(G$x*$vat,2))'), style(grey: true, money: true));
    put(r, 8, FormulaCellValue('IF(OR(E$x="",G$x=""),"",ROUND(E$x*G$x,2))'), style(grey: true, money: true));
    put(r, 9, FormulaCellValue('IF(I$x="","",ROUND(I$x*$vat,2))'), style(grey: true, money: true));
    if (withIds) put(r, 10, TextCellValue(item!.id), style(grey: true));
  }

  const widths = [6.0, 18.0, 26.0, 48.0, 11.0, 10.0, 12.0, 14.0, 14.0, 16.0, 40.0];
  for (var c = 0; c < headers.length; c++) {
    sheet.setColumnWidth(c, widths[c]);
  }

  // excel 4.0.6 only writes rightToLeft for a sheet that already exists in
  // the file's XML, which a sheet created in this session doesn't. One
  // encode → decode round trip makes it exist; then RTL sticks.
  final reopened = Excel.decodeBytes(excel.encode()!);
  reopened[sheetName].isRTL = true;
  return Uint8List.fromList(reopened.encode()!);
}

// ── Upload ────────────────────────────────────────────────────────────────────

class BoqRowError {
  final int rowNumber;
  final List<String> errors;
  final String preview;
  const BoqRowError({required this.rowNumber, required this.errors, required this.preview});
}

class BoqParseResult {
  /// The rows to apply. Rows with errors are left out, as in the inventory
  /// import: nothing is deleted, so skipping a row loses nothing. sortOrder
  /// holds the number to display; apply never sends it to the server.
  final List<ProjectItem> items;

  /// The spreadsheet row of each of [items].
  final List<int> rowNumbers;
  final List<BoqRowError> errors;

  /// Update file rows that match the current line exactly.
  final int unchangedCount;

  /// Why the whole file was refused, e.g. it isn't made from our template.
  final String? fileError;

  const BoqParseResult({
    required this.items,
    required this.rowNumbers,
    required this.errors,
    this.unchangedCount = 0,
    this.fileError,
  });

  const BoqParseResult.refused(String this.fileError)
    : items = const [],
      rowNumbers = const [],
      errors = const [],
      unchangedCount = 0;

  int get totalRows => items.length + errors.length + unchangedCount;
  bool get canApply => items.isNotEmpty && fileError == null;
}

const _notOurFile = 'هذا الملف ليس من قالب البنود. نزّل القالب من هذه الشاشة ثم انقل بياناتك إليه.';

enum _Col { id, category, name, description, quantity, unit, unitPrice }

class _Table {
  final Map<_Col, int> columns;
  final List<List<Data?>> rows;
  final int firstDataRow;
  const _Table(this.columns, this.rows, this.firstDataRow);
}

/// Finds the header row on the first sheet, or null if it isn't one of ours.
/// Columns are located by their exact text, so moving one in Excel is harmless.
_Table? _findTable(Uint8List bytes) {
  final excel = Excel.decodeBytes(sanitizeXlsx(bytes));
  if (excel.tables.isEmpty) return null;
  final rows = excel.tables.values.first.rows;
  const required = {
    'الفئة': _Col.category,
    'البند *': _Col.name,
    'وصف البند': _Col.description,
    'الكمية': _Col.quantity,
    'الوحدة *': _Col.unit,
    'سعر الوحدة': _Col.unitPrice,
  };
  for (var r = 0; r < rows.length && r <= _headerRow + 2; r++) {
    final texts = [for (final cell in rows[r]) _text(cell?.value)];
    if (!required.keys.every(texts.contains)) continue;
    final idColumn = texts.indexOf(_idHeader);
    return _Table(
      {
        for (final e in required.entries) e.value: texts.indexOf(e.key),
        if (idColumn >= 0) _Col.id: idColumn,
      },
      rows,
      r + 1,
    );
  }
  return null;
}

class _Line {
  final String id;
  final String category;
  final String name;
  final String? description;
  final String unit;
  final double quantity;
  final double? unitPrice;
  final List<String> errors;
  const _Line({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.errors,
  });

  String get preview => [name, description ?? ''].where((s) => s.isNotEmpty).join(' - ');
}

/// Reads one row, or null for a blank one (spare rows hold only formulas in
/// the م and grey columns, which aren't looked at here). Only the name and
/// unit are required; a blank quantity is stored as 0 and shown blank.
_Line? _readLine(List<Data?> row, Map<_Col, int> columns) {
  CellValue? value(_Col c) {
    final i = columns[c];
    return i == null || i >= row.length ? null : row[i]?.value;
  }

  if (_Col.values.every((c) => _isBlank(value(c)))) return null;

  final errors = <String>[];
  final name = _clean(_text(value(_Col.name)));
  final unit = _clean(_text(value(_Col.unit)));
  if (name.isEmpty) errors.add('اسم البند مفقود');
  if (unit.isEmpty) errors.add('الوحدة مفقودة');

  double? numberOrError(CellValue? raw, {required String formula, required String notNumber, required String negative}) {
    if (raw is FormulaCellValue) {
      // We can't read its result, and treating it as blank would wipe the
      // value on an update.
      errors.add(formula);
      return null;
    }
    if (_text(raw).isEmpty) return null;
    final n = _number(raw);
    if (n == null) {
      errors.add('$notNumber: ${_text(raw)}');
    } else if (n < 0) {
      errors.add(negative);
    }
    return n;
  }

  final quantity = numberOrError(
    value(_Col.quantity),
    formula: 'الكمية معادلة، اكتبها رقماً',
    notNumber: 'الكمية ليست رقماً',
    negative: 'الكمية سالبة',
  );
  final unitPrice = numberOrError(
    value(_Col.unitPrice),
    formula: 'سعر الوحدة معادلة، اكتبه رقماً',
    notNumber: 'سعر الوحدة ليس رقماً',
    negative: 'سعر الوحدة سالب',
  );
  final description = _clean(_text(value(_Col.description)));

  return _Line(
    id: _text(value(_Col.id)).toLowerCase(),
    category: _clean(_text(value(_Col.category))),
    name: name,
    description: description.isEmpty ? null : description,
    unit: unit,
    quantity: quantity ?? 0,
    unitPrice: unitPrice,
    errors: errors,
  );
}

double? _lineTotal(double quantity, double? unitPrice) =>
    unitPrice == null || quantity == 0 ? null : round2(quantity * unitPrice);

/// Two lines are the same line when all of these match, however they're spelled.
String _lineKey(String category, String name, String? description, String unit) =>
    [category, name, description ?? '', unit].map(foldForSearch).join('|');

/// Reads a filled template into new lines. A line that the project already has
/// or that the file repeats is an error, so uploading the same file twice
/// can't double the quotation.
BoqParseResult parseBoqTemplate(
  Uint8List bytes, {
  required String projectId,
  List<ProjectItem> existing = const [],
}) {
  final table = _findTable(bytes);
  if (table == null) return const BoqParseResult.refused(_notOurFile);
  if (table.columns.containsKey(_Col.id)) {
    return const BoqParseResult.refused('هذا ملف تعديل البنود الحالية. ارفعه من "تعديل البنود الحالية".');
  }

  final existingKeys = {
    for (final i in existing) _lineKey(i.category, i.itemName, i.description, i.unit),
  };
  final fileKeys = <String>{};
  final items = <ProjectItem>[];
  final rowNumbers = <int>[];
  final errors = <BoqRowError>[];

  for (var r = table.firstDataRow; r < table.rows.length; r++) {
    final line = _readLine(table.rows[r], table.columns);
    if (line == null) continue;
    final problems = [...line.errors];
    if (problems.isEmpty) {
      final key = _lineKey(line.category, line.name, line.description, line.unit);
      if (existingKeys.contains(key)) {
        problems.add('البند موجود مسبقاً في المشروع');
      } else if (!fileKeys.add(key)) {
        problems.add('البند مكرر في الملف');
      }
    }
    if (problems.isNotEmpty) {
      errors.add(BoqRowError(rowNumber: r + 1, errors: problems, preview: line.preview));
      continue;
    }
    items.add(ProjectItem(
      id: '',
      projectId: projectId,
      category: line.category,
      sortOrder: existing.length + items.length + 1,
      itemName: line.name,
      description: line.description,
      quantity: line.quantity,
      unit: line.unit,
      unitPrice: line.unitPrice,
      totalPrice: _lineTotal(line.quantity, line.unitPrice),
    ));
    rowNumbers.add(r + 1);
  }
  return BoqParseResult(items: items, rowNumbers: rowNumbers, errors: errors);
}

/// Reads an exported file into updates of [current], matched by id. Only rows
/// that actually changed are returned. A line left out of the file stays as it
/// is, and a row with no id is an error: this file doesn't add lines.
BoqParseResult parseBoqUpdateFile(Uint8List bytes, {required List<ProjectItem> current}) {
  final table = _findTable(bytes);
  if (table == null) return const BoqParseResult.refused(_notOurFile);
  if (!table.columns.containsKey(_Col.id)) {
    return const BoqParseResult.refused(
      'هذا الملف بلا عمود الرقم التعريفي. صدّر البنود الحالية من هذه الشاشة وعدّل عليها، ولإضافة بنود جديدة استخدم "إضافة بنود جديدة".',
    );
  }

  final positions = {for (var i = 0; i < current.length; i++) current[i].id.toLowerCase(): i};
  final seenIds = <String>{};
  final items = <ProjectItem>[];
  final rowNumbers = <int>[];
  final errors = <BoqRowError>[];
  var unchanged = 0;

  for (var r = table.firstDataRow; r < table.rows.length; r++) {
    final line = _readLine(table.rows[r], table.columns);
    if (line == null) continue;
    final problems = [...line.errors];
    if (line.id.isEmpty) {
      problems.add('الرقم التعريفي مفقود. لإضافة بند جديد استخدم "إضافة بنود جديدة"');
    } else if (!positions.containsKey(line.id)) {
      problems.add('لم يتم العثور على بند بهذا الرقم التعريفي');
    } else if (!seenIds.add(line.id)) {
      problems.add('الرقم التعريفي مكرر في الملف');
    }
    if (problems.isNotEmpty) {
      errors.add(BoqRowError(rowNumber: r + 1, errors: problems, preview: line.preview));
      continue;
    }

    final position = positions[line.id]!;
    final old = current[position];
    // A line can carry a total that isn't quantity × price, from a file
    // imported before totals were always computed. Exporting and re-uploading
    // it unedited mustn't rewrite it, so it's only recomputed on a real change.
    final pricingEdited = line.quantity != old.quantity || line.unitPrice != old.unitPrice;
    final total = pricingEdited ? _lineTotal(line.quantity, line.unitPrice) : old.totalPrice;
    if (!pricingEdited &&
        line.category == old.category &&
        line.name == old.itemName &&
        line.description == old.description &&
        line.unit == old.unit) {
      unchanged++;
      continue;
    }

    items.add(ProjectItem(
      id: old.id,
      projectId: old.projectId,
      category: line.category,
      sortOrder: position + 1,
      itemName: line.name,
      description: line.description,
      quantity: line.quantity,
      unit: line.unit,
      unitPrice: line.unitPrice,
      totalPrice: total,
      packagingUnitSize: old.packagingUnitSize,
      packagingUnitCount: old.packagingUnitCount,
      packagingBaseUnit: old.packagingBaseUnit,
      createdAt: old.createdAt,
    ));
    rowNumbers.add(r + 1);
  }
  return BoqParseResult(items: items, rowNumbers: rowNumbers, errors: errors, unchangedCount: unchanged);
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

/// A formula is not blank: someone put it there, and [_text] can't read it.
bool _isBlank(CellValue? v) => v is! FormulaCellValue && _text(v).isEmpty;

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
