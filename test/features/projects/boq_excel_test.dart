import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/projects/logic/boq_excel.dart';
import 'package:ura_core/shared/models/project_item.dart';

/// Column indices of the files, as a person sees them in Excel.
const _category = 1, _name = 2, _description = 3, _quantity = 4, _unit = 5, _price = 6, _id = 10;

Uint8List _template({int firstNumber = 1}) =>
    buildBoqTemplate(projectName: 'مشروع', entityName: 'جهة', firstNumber: firstNumber);

Uint8List _updateFile(List<ProjectItem> items) =>
    buildBoqUpdateFile(projectName: 'مشروع', entityName: 'جهة', items: items);

int _firstDataRow(Excel excel) =>
    excel.tables.values.first.rows.indexWhere((r) => r.any((c) => c?.value.toString() == 'البند *')) + 1;

/// Opens [file], lets [edit] write cells relative to the first data row, the
/// way a person would in Excel, and saves it.
Uint8List _edit(Uint8List file, void Function(void Function(int row, int col, CellValue v) set) edit) {
  final excel = Excel.decodeBytes(file);
  final sheet = excel.tables.values.first;
  final first = _firstDataRow(excel);
  edit((row, col, v) => sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: first + row)).value = v);
  return Uint8List.fromList(excel.encode()!);
}

const _bread = ProjectItem(
  id: '11111111-1111-1111-1111-111111111111',
  projectId: 'p',
  category: 'المخبوزات',
  sortOrder: 4,
  itemName: 'خبز',
  description: 'وسط',
  quantity: 10,
  unit: 'كيس',
  unitPrice: 1.25,
  totalPrice: 12.5,
  packagingUnitSize: 1.65,
  packagingUnitCount: 4,
  packagingBaseUnit: 'kilogram',
);
const _charcoal = ProjectItem(
  id: '22222222-2222-2222-2222-222222222222',
  projectId: 'p',
  category: 'الفحم',
  sortOrder: 9,
  itemName: 'فحم',
  quantity: 0,
  unit: 'شوال',
);

void main() {
  group('template', () {
    test('has the file headers, numbers itself, and reads back as no rows', () {
      final template = _template(firstNumber: 11);
      final excel = Excel.decodeBytes(template);
      final rows = excel.tables.values.first.rows;
      final header = _firstDataRow(excel) - 1;
      expect(
        [for (final c in rows[header]) c?.value.toString()].whereType<String>().toList(),
        ['م', 'الفئة', 'البند *', 'وصف البند', 'الكمية', 'الوحدة *', 'سعر الوحدة', 'سعر الوحدة شامل الضريبة', 'الإجمالي', 'الإجمالي شامل الضريبة'],
      );
      // Excel row 4 is the first data row, and this project has 10 lines.
      expect(rows[header + 1][0]?.value.toString(), contains('ROW()-3+10'));

      final parsed = parseBoqTemplate(template, projectId: 'p');
      expect(parsed.fileError, isNull);
      expect(parsed.totalRows, 0, reason: 'spare formula rows are not lines');
    });

    test('name and unit are enough; quantity and price stay optional', () {
      final file = _edit(_template(), (set) {
        set(0, _name, TextCellValue('أرز بسمتي'));
        set(0, _unit, TextCellValue('كيس'));
      });
      final result = parseBoqTemplate(file, projectId: 'p');
      expect(result.errors, isEmpty);
      final item = result.items.single;
      expect(item.id, '');
      expect(item.itemName, 'أرز بسمتي');
      expect(item.unit, 'كيس');
      expect(item.quantity, 0);
      expect(item.unitPrice, isNull);
      expect(item.totalPrice, isNull);
      expect(item.description, isNull);
      expect(item.category, '');
    });

    test('reads every field; the total is computed; Arabic digits and commas work', () {
      final file = _edit(_template(), (set) {
        set(0, _category, TextCellValue('المخبوزات'));
        set(0, _name, TextCellValue('خبز عربي'));
        set(0, _description, TextCellValue('انتاج اليوم'));
        set(0, _quantity, TextCellValue('٥٠٬٧٠٠٫٠٠'));
        set(0, _unit, TextCellValue('كيس'));
        set(0, _price, DoubleCellValue(1.25));
      });
      final item = parseBoqTemplate(file, projectId: 'p').items.single;
      expect(item.category, 'المخبوزات');
      expect(item.description, 'انتاج اليوم');
      expect(item.quantity, 50700);
      expect(item.unitPrice, 1.25);
      expect(item.totalPrice, 63375);
    });

    test('numbers carry on after the existing lines and rows report their Excel row', () {
      final file = _edit(_template(), (set) {
        set(0, _name, TextCellValue('أرز'));
        set(0, _unit, TextCellValue('كيس'));
        set(2, _name, TextCellValue('سكر'));
        set(2, _unit, TextCellValue('كيس'));
      });
      final result = parseBoqTemplate(file, projectId: 'p', existing: const [_bread, _charcoal]);
      expect(result.items.map((i) => i.sortOrder), [3, 4]);
      expect(result.rowNumbers, [4, 6]);
    });

    test('bad rows are listed with their Excel row while good ones still go in', () {
      final file = _edit(_template(), (set) {
        set(0, _name, TextCellValue('صنف جيد'));
        set(0, _unit, TextCellValue('حبة'));
        set(1, _name, TextCellValue('بدون وحدة'));
        set(2, _unit, TextCellValue('حبة'));
        set(3, _name, TextCellValue('كمية خطأ'));
        set(3, _unit, TextCellValue('حبة'));
        set(3, _quantity, TextCellValue('كثير'));
        set(4, _name, TextCellValue('سعر سالب'));
        set(4, _unit, TextCellValue('حبة'));
        set(4, _price, DoubleCellValue(-5));
        set(5, _name, TextCellValue('كمية معادلة'));
        set(5, _unit, TextCellValue('حبة'));
        set(5, _quantity, FormulaCellValue('2*3'));
      });
      final result = parseBoqTemplate(file, projectId: 'p');
      expect(result.items.single.itemName, 'صنف جيد');
      expect(result.canApply, isTrue);
      expect(result.errors.map((e) => e.rowNumber), [5, 6, 7, 8, 9]);
      expect(result.errors[0].errors, contains('الوحدة مفقودة'));
      expect(result.errors[1].errors, contains('اسم البند مفقود'));
      expect(result.errors[2].errors.single, startsWith('الكمية ليست رقماً'));
      expect(result.errors[3].errors.single, 'سعر الوحدة سالب');
      expect(result.errors[4].errors.single, contains('معادلة'));
      expect(result.totalRows, 6);
    });

    test('a file with only bad rows cannot be applied', () {
      final file = _edit(_template(), (set) => set(0, _name, TextCellValue('بدون وحدة')));
      expect(parseBoqTemplate(file, projectId: 'p').canApply, isFalse);
    });

    test('a line the project has, or the file repeats, is flagged however it is spelled', () {
      final file = _edit(_template(), (set) {
        // Same as _bread: the spelling folds to the same text.
        set(0, _category, TextCellValue('المخبوزات'));
        set(0, _name, TextCellValue('خبز'));
        set(0, _description, TextCellValue('وسط'));
        set(0, _unit, TextCellValue('كيس'));
        // Same name, another description: a different line.
        set(1, _category, TextCellValue('المخبوزات'));
        set(1, _name, TextCellValue('خبز'));
        set(1, _description, TextCellValue('كبير'));
        set(1, _unit, TextCellValue('كيس'));
        // Repeats the line above.
        set(2, _category, TextCellValue('المخبوزات'));
        set(2, _name, TextCellValue('خبز'));
        set(2, _description, TextCellValue('كبير'));
        set(2, _unit, TextCellValue('كيس'));
      });
      final result = parseBoqTemplate(file, projectId: 'p', existing: const [_bread]);
      expect(result.items.single.description, 'كبير');
      expect(result.errors.map((e) => e.errors.single), ['البند موجود مسبقاً في المشروع', 'البند مكرر في الملف']);
    });

    test('Persian-keyboard letters are folded to Arabic', () {
      final file = _edit(_template(), (set) {
        set(0, _category, TextCellValue('الحلیب ومشتقاتھ'));
        set(0, _name, TextCellValue('لبنة'));
        set(0, _unit, TextCellValue('کرتون'));
      });
      final item = parseBoqTemplate(file, projectId: 'p').items.single;
      expect(item.category, 'الحليب ومشتقاته');
      expect(item.unit, 'كرتون');
    });
  });

  group('refused files', () {
    Uint8List foreign(List<String> header) {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      for (var c = 0; c < header.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(header[c]);
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('أرز');
      return Uint8List.fromList(excel.encode()!);
    }

    test('any other Excel is refused in both flows, even with the right column names', () {
      for (final header in [
        ['اسم'],
        ['البند', 'الوحدة'],
        ['م', 'البند', 'وصف البند', 'الكمية', 'الوحدة', 'سعر الوحدة'],
      ]) {
        final file = foreign(header);
        final add = parseBoqTemplate(file, projectId: 'p');
        final update = parseBoqUpdateFile(file, current: const [_bread]);
        expect(add.fileError, contains('قالب'), reason: '$header');
        expect(update.fileError, contains('قالب'), reason: '$header');
        expect(add.canApply, isFalse);
        expect(update.canApply, isFalse);
      }
    });

    test('the update file is refused in the add flow and the template in the update flow', () {
      final add = parseBoqTemplate(_updateFile(const [_bread]), projectId: 'p');
      expect(add.fileError, contains('تعديل البنود الحالية'));
      expect(add.items, isEmpty);

      final update = parseBoqUpdateFile(_template(), current: const [_bread]);
      expect(update.fileError, contains('إضافة بنود جديدة'));
    });
  });

  group('update file', () {
    test('an untouched export changes nothing', () {
      final result = parseBoqUpdateFile(_updateFile(const [_bread, _charcoal]), current: const [_bread, _charcoal]);
      expect(result.fileError, isNull);
      expect(result.errors, isEmpty);
      expect(result.items, isEmpty);
      expect(result.unchangedCount, 2);
      expect(result.canApply, isFalse);
    });

    test('an edited row keeps its id and packaging, is renumbered for display, and recomputes its total', () {
      final file = _edit(_updateFile(const [_charcoal, _bread]), (set) {
        set(1, _quantity, DoubleCellValue(20));
        set(1, _name, TextCellValue('خبز عربي'));
      });
      final result = parseBoqUpdateFile(file, current: const [_charcoal, _bread]);
      expect(result.unchangedCount, 1);
      expect(result.rowNumbers, [5]);
      final item = result.items.single;
      expect(item.id, _bread.id);
      expect(item.itemName, 'خبز عربي');
      expect(item.quantity, 20);
      expect(item.totalPrice, 25);
      expect(item.sortOrder, 2, reason: 'its position, for the preview');
      expect(item.packagingUnitSize, 1.65);
      expect(item.packagingUnitCount, 4);
      expect(item.packagingBaseUnit, 'kilogram');
    });

    test('what goes to the server never includes sort order or packaging', () {
      final json = _bread.toApplyJson(rowNumber: 7);
      expect(json['id'], _bread.id);
      expect(json['row_number'], 7);
      expect(json.keys, isNot(contains('sort_order')));
      expect(json.keys.where((k) => k.startsWith('packaging')), isEmpty);

      const added = ProjectItem(id: '', projectId: 'p', itemName: 'أرز', quantity: 0, unit: 'كيس');
      expect(added.toApplyJson().keys, isNot(contains('id')));
    });

    test('clearing quantity and price clears them and the total', () {
      final file = Excel.decodeBytes(_updateFile(const [_bread]));
      final sheet = file.tables.values.first;
      final row = _firstDataRow(file);
      sheet.removeRow(row);
      for (final (col, value) in [
        (_name, _bread.itemName),
        (_unit, _bread.unit),
        (_category, _bread.category),
        (_description, _bread.description!),
        (_id, _bread.id),
      ]) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = TextCellValue(value);
      }
      final item = parseBoqUpdateFile(Uint8List.fromList(file.encode()!), current: const [_bread]).items.single;
      expect(item.quantity, 0);
      expect(item.unitPrice, isNull);
      expect(item.totalPrice, isNull);
    });

    test('a line whose total is not quantity × price is left alone until its pricing changes', () {
      const lumpSum = ProjectItem(id: 'aaaa', projectId: 'p', itemName: 'نقل', quantity: 0, unit: 'رحلة', totalPrice: 900);
      expect(parseBoqUpdateFile(_updateFile(const [lumpSum]), current: const [lumpSum]).unchangedCount, 1);

      final renamed = _edit(_updateFile(const [lumpSum]), (set) => set(0, _name, TextCellValue('نقل بري')));
      expect(parseBoqUpdateFile(renamed, current: const [lumpSum]).items.single.totalPrice, 900);

      final priced = _edit(_updateFile(const [lumpSum]), (set) {
        set(0, _quantity, DoubleCellValue(2));
        set(0, _price, DoubleCellValue(100));
      });
      expect(parseBoqUpdateFile(priced, current: const [lumpSum]).items.single.totalPrice, 200);
    });

    test('a row left out of the file leaves that line alone', () {
      final result = parseBoqUpdateFile(_updateFile(const [_bread]), current: const [_bread, _charcoal]);
      expect(result.items, isEmpty);
      expect(result.errors, isEmpty);
      expect(result.unchangedCount, 1);
    });

    test('missing, unknown and repeated ids are errors with no write', () {
      final file = _edit(_updateFile(const [_bread, _charcoal]), (set) {
        set(0, _id, TextCellValue('99999999-9999-9999-9999-999999999999'));
        set(1, _id, TextCellValue(_bread.id.toUpperCase()));
        set(2, _id, TextCellValue(_bread.id));
        set(2, _name, TextCellValue('نفس البند'));
        set(2, _unit, TextCellValue('حبة'));
        set(3, _name, TextCellValue('بدون رقم'));
        set(3, _unit, TextCellValue('حبة'));
      });
      final result = parseBoqUpdateFile(file, current: const [_bread, _charcoal]);
      expect(result.errors.map((e) => e.errors.single), [
        'لم يتم العثور على بند بهذا الرقم التعريفي',
        'الرقم التعريفي مكرر في الملف',
        'الرقم التعريفي مفقود. لإضافة بند جديد استخدم "إضافة بنود جديدة"',
      ]);
      // Row 1 matched _bread despite the case, and its other cells are _charcoal's.
      expect(result.items.single.id, _bread.id);
      expect(result.items.single.itemName, 'فحم');
    });

    test('a row with only its name wiped is an error, not a blank line', () {
      final file = Excel.decodeBytes(_updateFile(const [_bread]));
      final sheet = file.tables.values.first;
      final row = _firstDataRow(file);
      sheet.removeRow(row);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: _id, rowIndex: row)).value = TextCellValue(_bread.id);
      final result = parseBoqUpdateFile(Uint8List.fromList(file.encode()!), current: const [_bread]);
      expect(result.items, isEmpty);
      expect(result.errors.single.errors, containsAll(['اسم البند مفقود', 'الوحدة مفقودة']));
    });
  });

  group('files saved by other programs', () {
    Uint8List rewrite(Uint8List original, String name, String Function(String) change) {
      final archive = ZipDecoder().decodeBytes(original);
      final rebuilt = Archive();
      for (final f in archive.files) {
        if (f.name == name) {
          final data = utf8.encode(change(utf8.decode(f.content as List<int>)));
          rebuilt.addFile(ArchiveFile(f.name, data.length, data));
        } else {
          rebuilt.addFile(f);
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(rebuilt)!);
    }

    Uint8List filled() => _edit(_template(), (set) {
          set(0, _name, TextCellValue('دجاج'));
          set(0, _unit, TextCellValue('كرتون'));
          set(0, _quantity, DoubleCellValue(60));
          set(0, _price, DoubleCellValue(123));
        });

    test('opens files saved by Microsoft Excel (numFmtId 41-44 in styles.xml)', () {
      // styles.xml edited the way Excel rewrites it: a custom accounting
      // format declared with id 43, and cells pointing at 43/44.
      const accounting = r'<numFmt numFmtId="43" formatCode="_(* #,##0.00_);_(* \(#,##0.00\);_(* &quot;-&quot;??_);_(@_)"/>';
      final bytes = rewrite(filled(), 'xl/styles.xml', (styles) {
        final declared = styles.contains('<numFmts')
            ? styles.replaceFirst(RegExp(r'<numFmts[^>]*>'), '<numFmts count="1">$accounting')
            : styles.replaceFirst('<fonts', '<numFmts count="1">$accounting</numFmts><fonts');
        return declared.replaceAll('numFmtId="4"', 'numFmtId="43"').replaceFirst('numFmtId="0"', 'numFmtId="44"');
      });

      expect(() => Excel.decodeBytes(bytes), throwsA(anything), reason: 'reproduces the crash seen in the app');

      final result = parseBoqTemplate(bytes, projectId: 'p');
      expect(result.errors, isEmpty);
      expect(result.items.single.itemName, 'دجاج');
      expect(result.items.single.totalPrice, 7380);
    });

    test('opens files whose sheet paths are absolute (LibreOffice / openpyxl)', () {
      final bytes = rewrite(filled(), 'xl/_rels/workbook.xml.rels', (xml) => xml.replaceAll('Target="', 'Target="/xl/'));

      expect(() => Excel.decodeBytes(bytes), throwsA(anything));
      expect(parseBoqTemplate(bytes, projectId: 'p').items.single.totalPrice, 7380);
    });
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
}
