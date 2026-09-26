import 'dart:io';
import 'dart:typed_data';
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

  test('VAT matches the paper quotation to the halala', () {
    const item = ProjectItem(id: '', projectId: '', itemName: 'x', quantity: 1, unit: 'u', totalPrice: 533870.70);
    final t = BoqTotals.of([item]);
    expect(t.subtotal, 533870.70);
    expect(t.vat, 80080.61);
    expect(t.total, 613951.31);

    const coal = ProjectItem(id: '', projectId: '', itemName: 'x', quantity: 1, unit: 'u', totalPrice: 557400);
    expect(BoqTotals.of([coal]).vat, 83610);
  });
}
