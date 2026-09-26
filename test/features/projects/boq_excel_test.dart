import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/projects/logic/boq_excel.dart';
import 'package:ura_core/shared/models/project_item.dart';

/// Builds a workbook the way Ahmed's real quotations look: columns in a
/// different order from our export, text numbers with thousands commas,
/// descriptions that themselves contain "اجمالي", totals rows, blank rows.
Uint8List ahmedStyleWorkbook() {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  void row(int r, List<Object?> cells) {
    for (var c = 0; c < cells.length; c++) {
      final v = cells[c];
      if (v == null) continue;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = switch (v) {
        int() => IntCellValue(v),
        double() => DoubleCellValue(v),
        _ => TextCellValue(v.toString()),
      };
    }
  }

  // السعر الإجمالي | السعر الافرادي | الوحدة | الكمية | وصف البند | البند | م
  row(0, [null, null, null, null, null, null, 'جدول الكميات : المخبوزات']);
  row(1, ['السعر الإجمالي', 'السعر\nالافرادي', 'الوحدة', 'الكمية', 'وصف البند', 'البند', 'م']);
  row(2, ['63,375.00', '1.25', 'كيس', '50,700.00', 'انتاج اليوم حجم متوسط مقاس 25 سم / 8حبة', 'خبز عربي أبيض وسط', 1]);
  row(3, [79200.0, 4, 'كيس', 19800, 'انتاج اليوم وزن اجمالي 700 جم/ 21شريحة', 'خبز توست أبيض', 2]);
  row(4, ['١٬٨٧٥٫٠٠', '٥', 'كيس', '٣٧٥', null, 'خبز برانا', 3]);
  row(5, [null, null, null, null, null, null, 4]); // blank template row
  row(6, [144450.0, null, null, null, 'الإجمالي غير شامل ضريبة القيمة المضافة']);
  row(7, [21667.5, null, null, null, 'قيمة الضريبة المضافة']);
  row(8, [166117.5, null, null, null, 'الإجمالي شامل ضريبة القيمة المضافة']);
  row(10, [null, null, null, null, null, null, 'جدول الكميات : الفحم ومواد الاشعال']);
  row(11, ['السعر الإجمالي', 'السعر الافرادي', 'الوحدة', 'الكمية', 'وصف البند', 'البند', 'م']);
  row(12, [162000.0, 45, 'شوال', 3600, 'فحم طبيعي درجة أولى 10كيلو جرام', 'فحم للمشاوي', 1]);
  row(13, [null, 70, 'كرتون', 20, null, 'فحم صناعي دائري', 2]); // no total -> computed
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  test('reads a real-shaped quotation: categories, header-by-name, text numbers, totals skipped', () {
    final result = parseBoqWorkbook(ahmedStyleWorkbook());

    expect(result.errors, isEmpty);
    expect(result.noHeaderFound, isFalse);
    expect(result.items.map((i) => i.itemName).toList(), [
      'خبز عربي أبيض وسط',
      'خبز توست أبيض',
      'خبز برانا',
      'فحم للمشاوي',
      'فحم صناعي دائري',
    ]);

    final bread = result.items[0];
    expect(bread.category, 'المخبوزات');
    expect(bread.quantity, 50700);
    expect(bread.unitPrice, 1.25);
    expect(bread.totalPrice, 63375);
    expect(bread.unit, 'كيس');
    expect(bread.description, 'انتاج اليوم حجم متوسط مقاس 25 سم / 8حبة');

    // "وزن اجمالي" in a description must not be mistaken for a totals row.
    expect(result.items[1].description, contains('اجمالي'));

    final arabicDigits = result.items[2];
    expect(arabicDigits.quantity, 375);
    expect(arabicDigits.unitPrice, 5);
    expect(arabicDigits.totalPrice, 1875);

    expect(result.items[4].category, 'الفحم ومواد الاشعال');
    expect(result.items[4].totalPrice, 1400, reason: 'missing total is qty × unit price');

    expect(result.items.map((i) => i.sortOrder).toList(), [1, 2, 3, 4, 5]);
    expect(result.categories.map((c) => c.name).toList(), ['المخبوزات', 'الفحم ومواد الاشعال']);
    expect(result.canImport, isTrue);
  });

  test('export then import round-trips categories, order, quantities and prices', () {
    const items = [
      ProjectItem(id: 'a', projectId: 'p', category: 'المخبوزات', itemName: 'خبز', description: 'وسط', quantity: 10, unit: 'كيس', unitPrice: 1.25, totalPrice: 12.5),
      ProjectItem(id: 'b', projectId: 'p', category: 'المخبوزات', itemName: 'كيك', quantity: 3, unit: 'كرتون', unitPrice: 8, totalPrice: 24),
      ProjectItem(id: 'c', projectId: 'p', category: 'الفحم', itemName: 'فحم', quantity: 2.5, unit: 'شوال', unitPrice: 45, totalPrice: 112.5),
      ProjectItem(id: 'd', projectId: 'p', itemName: 'بدون فئة', quantity: 1, unit: 'حبة'),
    ];
    final bytes = buildBoqWorkbook(projectName: 'مشروع', entityName: 'جهة', items: items);
    final out = Platform.environment['BOQ_XLSX_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);

    final result = parseBoqWorkbook(bytes);
    expect(result.errors, isEmpty);
    expect(result.items.length, 4);
    for (var i = 0; i < items.length; i++) {
      final a = items[i], b = result.items[i];
      expect(b.category, a.category);
      expect(b.itemName, a.itemName);
      expect(b.description, a.description);
      expect(b.quantity, a.quantity);
      expect(b.unit, a.unit);
      expect(b.unitPrice, a.unitPrice);
      expect(b.totalPrice, a.totalPrice);
    }
  });

  test('an empty project exports the fill-in model: headers, formulas, nothing else', () {
    final template = buildBoqWorkbook(projectName: 'مشروع', entityName: 'جهة', items: const []);
    final out = Platform.environment['BOQ_TEMPLATE_OUT'];
    if (out != null) File(out).writeAsBytesSync(template);

    final empty = parseBoqWorkbook(template);
    expect(empty.noHeaderFound, isFalse, reason: 'the template must carry the header row');
    expect(empty.items, isEmpty);
    expect(empty.errors, isEmpty, reason: 'spare formula rows are not errors');

    final sheet = Excel.decodeBytes(template).tables.values.first;
    final headerRow = sheet.rows.indexWhere((r) => r.any((c) => c?.value.toString() == 'البند'));
    expect(
      [for (final c in sheet.rows[headerRow]) c?.value.toString()].whereType<String>().toList(),
      boqHeaders,
    );

    // Fill one line the way a person would in Excel.
    final excel = Excel.decodeBytes(template);
    final s = excel.tables.values.first;
    final r = headerRow + 1;
    void set(int c, CellValue v) => s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = v;
    set(0, TextCellValue('المخبوزات'));
    set(1, TextCellValue('خبز عربي'));
    set(3, IntCellValue(100));
    set(4, TextCellValue('كيس'));
    set(5, DoubleCellValue(1.25));

    final filled = parseBoqWorkbook(Uint8List.fromList(excel.encode()!));
    expect(filled.errors, isEmpty);
    final item = filled.items.single;
    expect(item.category, 'المخبوزات');
    expect(item.itemName, 'خبز عربي');
    expect(item.quantity, 100);
    expect(item.unitPrice, 1.25);
    expect(item.totalPrice, 125, reason: 'formula total is ignored and recomputed');
  });

  test('reads the PDF-style order sheet: الحزمة per row, Persian letters, no total column', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    void row(int r, List<Object> cells) {
      for (var c = 0; c < cells.length; c++) {
        final v = cells[c];
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value =
            v is num ? DoubleCellValue(v.toDouble()) : TextCellValue(v.toString());
      }
    }

    // Exactly the header text of طلبية_مواد_مختلطة (note the Persian ی/ھ).
    row(0, ['م', 'الحزمة', 'البند', 'وصف البند', 'الكمیة', 'الوحدة', 'السعر الافرادي']);
    row(1, [1, 'الحلیب ومشتقاتھ', 'لبنة', 'جودة عالیة / كرتون 4*2.75كیلو جرام', 5, 'كرتون', 180]);
    row(2, [8, 'مجمدات', 'ھاش براون', 'مجمدة إنتاج جديد', 5, 'كرتون', 140]);
    row(3, [36, 'الحلويات والمكسرات', 'مرقوق', 'درجة أولى', 600, 'بكت', 14]);

    final result = parseBoqWorkbook(Uint8List.fromList(excel.encode()!));
    expect(result.errors, isEmpty);
    expect(result.items.map((i) => i.category).toList(), ['الحليب ومشتقاته', 'مجمدات', 'الحلويات والمكسرات']);
    final labneh = result.items.first;
    expect(labneh.itemName, 'لبنة');
    expect(labneh.quantity, 5);
    expect(labneh.unitPrice, 180);
    expect(labneh.totalPrice, 900);
    expect(result.items[2].totalPrice, 8400);
    expect(result.categories.length, 3);
  });

  test('opens files saved by Microsoft Excel (numFmtId 41-44 in styles.xml)', () {
    // Our export, then styles.xml edited the way Excel rewrites it: a custom
    // accounting format declared with id 43, and cells pointing at 43/44.
    final original = buildBoqWorkbook(projectName: 'م', entityName: 'ج', items: const [
      ProjectItem(id: '', projectId: '', category: 'مجمدات', itemName: 'دجاج', quantity: 60, unit: 'كرتون', unitPrice: 123),
    ]);
    final archive = ZipDecoder().decodeBytes(original);
    final styles = utf8.decode(archive.findFile('xl/styles.xml')!.content as List<int>);
    const accounting = r'<numFmt numFmtId="43" formatCode="_(* #,##0.00_);_(* \(#,##0.00\);_(* &quot;-&quot;??_);_(@_)"/>';
    var excelSaved = styles.contains('<numFmts')
        ? styles.replaceFirst(RegExp(r'<numFmts[^>]*>'), '<numFmts count="1">$accounting')
        : styles.replaceFirst('<fonts', '<numFmts count="1">$accounting</numFmts><fonts');
    excelSaved = excelSaved.replaceAll('numFmtId="4"', 'numFmtId="43"');
    excelSaved = excelSaved.replaceFirst('numFmtId="0"', 'numFmtId="44"');
    final rebuilt = Archive();
    for (final f in archive.files) {
      if (f.name == 'xl/styles.xml') {
        final data = utf8.encode(excelSaved);
        rebuilt.addFile(ArchiveFile(f.name, data.length, data));
      } else {
        rebuilt.addFile(f);
      }
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(rebuilt)!);

    expect(() => Excel.decodeBytes(bytes), throwsA(anything), reason: 'reproduces the crash seen in the app');

    final result = parseBoqWorkbook(bytes);
    expect(result.errors, isEmpty);
    expect(result.items.single.itemName, 'دجاج');
    expect(result.items.single.totalPrice, 7380);
  });

  test('opens files whose sheet paths are absolute (LibreOffice / openpyxl)', () {
    final original = buildBoqWorkbook(projectName: 'م', entityName: 'ج', items: const [
      ProjectItem(id: '', projectId: '', itemName: 'تونة', quantity: 5, unit: 'كرتون', unitPrice: 170),
    ]);
    final archive = ZipDecoder().decodeBytes(original);
    final rebuilt = Archive();
    for (final f in archive.files) {
      if (f.name == 'xl/_rels/workbook.xml.rels') {
        final xml = utf8.decode(f.content as List<int>).replaceAll('Target="', 'Target="/xl/');
        final data = utf8.encode(xml);
        rebuilt.addFile(ArchiveFile(f.name, data.length, data));
      } else {
        rebuilt.addFile(f);
      }
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(rebuilt)!);

    expect(() => Excel.decodeBytes(bytes), throwsA(anything));
    expect(parseBoqWorkbook(bytes).items.single.totalPrice, 850);
  });

  test('bad rows are reported with their Excel row number and block the import', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    void put(int r, int c, String v) =>
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(v);
    const header = ['م', 'البند', 'وصف البند', 'الكمية', 'الوحدة', 'السعر الإفرادي', 'السعر الإجمالي'];
    for (var c = 0; c < header.length; c++) {
      put(0, c, header[c]);
    }
    put(1, 1, 'صنف جيد');
    put(1, 3, '5');
    put(1, 4, 'حبة');
    put(2, 1, 'بدون وحدة');
    put(2, 3, '2');
    put(3, 1, 'كمية خطأ');
    put(3, 3, 'كثير');
    put(3, 4, 'حبة');

    final result = parseBoqWorkbook(Uint8List.fromList(excel.encode()!));
    expect(result.items.single.itemName, 'صنف جيد');
    expect(result.errors.map((e) => e.rowNumber).toList(), [3, 4]);
    expect(result.errors[0].errors, contains('الوحدة مفقودة'));
    expect(result.errors[1].errors.single, startsWith('الكمية ليست رقماً'));
    expect(result.canImport, isFalse);
  });

  test('a sheet with no البند header is flagged as not a quotation', () {
    final excel = Excel.createExcel();
    excel['Sheet1'].cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('اسم');
    final result = parseBoqWorkbook(Uint8List.fromList(excel.encode()!));
    expect(result.noHeaderFound, isTrue);
    expect(result.canImport, isFalse);
  });

  test('search folds Arabic spelling variants and Persian letters, all words must match', () {
    const item = ProjectItem(
      id: '', projectId: '', category: 'الحلیب ومشتقاتھ', itemName: 'زبادي كامل الدسم',
      description: 'طازج مبرد / 170 جرام', quantity: 6, unit: 'عبوة',
    );
    final key = boqSearchKey(item);
    bool matches(String q) => foldForSearch(q).split(' ').where((w) => w.isNotEmpty).every(key.contains);

    expect(matches('زبادي'), isTrue);
    expect(matches('مشتقاته'), isTrue, reason: 'ھ in the file, ه typed');
    expect(matches('الحليب'), isTrue, reason: 'ی in the file, ي typed');
    expect(matches('عبوه'), isTrue, reason: 'ة vs ه');
    expect(matches('زبادي 170'), isTrue);
    expect(matches('زبادي لبنة'), isFalse, reason: 'every word must match');
  });

  test('a line mentioning tax is an item, not a totals row; اسم الصنف is a header', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    void row(int r, List<Object?> cells) {
      for (var c = 0; c < cells.length; c++) {
        final v = cells[c];
        if (v == null) continue;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value =
            v is num ? DoubleCellValue(v.toDouble()) : TextCellValue(v.toString());
      }
    }

    row(0, ['م', 'اسم الصنف', 'الوصف', 'الكمية', 'الوحدة', 'سعر الوحدة']);
    row(1, [1, 'طوابع ضريبية', 'السعر شامل الضريبة', 10, 'حبة', 5]);
    row(2, [null, 'الإجمالي غير شامل ضريبة القيمة المضافة', null, null, null, 50]);

    final result = parseBoqWorkbook(Uint8List.fromList(excel.encode()!));
    expect(result.noHeaderFound, isFalse);
    expect(result.errors, isEmpty);
    expect(result.items.single.itemName, 'طوابع ضريبية');
    expect(result.items.single.totalPrice, 50);
  });
}
