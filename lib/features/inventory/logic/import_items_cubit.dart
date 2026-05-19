import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../data/inventory_management_repository.dart';
import '../data/models/imported_item_model.dart';
import '../data/models/item_import_error_model.dart';
import 'import_items_state.dart';
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';

class ImportItemsCubit extends Cubit<ImportItemsState> {
  final InventoryManagementRepository _repo;

  ImportItemsCubit(this._repo) : super(ImportItemsInitial());

  Future<void> downloadTemplate() async {
    try {
      final bytes = _buildTemplateBytes();
      if (bytes == null) {
        emit(ImportItemsError('فشل إنشاء القالب'));
        return;
      }

      if (kIsWeb) {
        triggerWebDownload(bytes, 'قالب_المخزون.xlsx');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/قالب_المخزون.xlsx');
        await file.writeAsBytes(bytes);
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done) {
          logger.w('open_filex result: ${result.type} — ${result.message}');
        }
      }
    } catch (e, st) {
      logger.e('downloadTemplate failed', error: e, stackTrace: st);
      emit(ImportItemsError('فشل إنشاء القالب: ${e.toString()}'));
    }
  }

  List<int>? _buildTemplateBytes() {
    final excel = Excel.createExcel();
    final sheet = excel['المخزون'];
    excel.delete('Sheet1');

    final headers = [
      'الاسم *',
      'الوحدة *',
      'الكمية *',
      'الكود (SKU)',
      'الفئة',
      'حد التنبيه',
      'الوصف',
      'ملاحظات',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(bold: true);
    }

    final example = [
      'كيس إسمنت',
      'كيس',
      '50',
      'CEM-001',
      'بناء',
      '10',
      'أكياس إسمنت 50 كيلو',
      'ملاحظات اختيارية',
    ];
    for (var i = 0; i < example.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1));
      cell.value = TextCellValue(example[i]);
    }

    return excel.encode();
  }

  Future<void> pickAndParse() async {
    emit(ImportItemsParsing());
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        emit(ImportItemsInitial());
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        emit(ImportItemsError('تعذر قراءة الملف'));
        return;
      }

      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        emit(ImportItemsError('الملف فارغ أو لا يحتوي على بيانات'));
        return;
      }

      Set<String> existingSkus = {};
      final skusResult = await _repo.fetchExistingSkus();
      if (skusResult is AppSuccess<Set<String>>) {
        existingSkus = skusResult.data;
      }

      final validItems = <ImportedItemModel>[];
      final invalidItems = <ItemImportErrorModel>[];
      final seenSkusInFile = <String>{};
      int totalRows = 0;

      // Skip row 0 (header) and row 1 (example), start from row 2
      for (var rowIdx = 2; rowIdx < sheet.rows.length; rowIdx++) {
        final row = sheet.rows[rowIdx];

        String? cellStr(int col) {
          if (col >= row.length) return null;
          final v = row[col]?.value;
          if (v == null) return null;
          final s = v.toString().trim();
          return s.isEmpty ? null : s;
        }

        final item = ImportedItemModel(
          rowNumber: rowIdx + 1,
          name: cellStr(0),
          unit: cellStr(1),
          rawQuantity: cellStr(2),
          sku: cellStr(3),
          category: cellStr(4),
          rawAlarmLimit: cellStr(5),
          description: cellStr(6),
          notes: cellStr(7),
        );

        if (item.isEmpty) continue;
        totalRows++;

        final errors = _validate(item, existingSkus, seenSkusInFile);
        if (errors.isEmpty) {
          if (item.sku != null && item.sku!.isNotEmpty) {
            seenSkusInFile.add(item.sku!.toLowerCase());
          }
          validItems.add(item);
        } else {
          invalidItems.add(ItemImportErrorModel(
            rowNumber: item.rowNumber,
            errors: errors,
            rawData: item,
          ));
        }
      }

      if (totalRows == 0) {
        emit(ImportItemsError('لم يتم العثور على صفوف بيانات في الملف'));
        return;
      }

      emit(ImportItemsParsed(
        validItems: validItems,
        invalidItems: invalidItems,
        totalRows: totalRows,
      ));
    } catch (e, st) {
      logger.e('pickAndParse failed', error: e, stackTrace: st);
      emit(ImportItemsError('فشل تحليل الملف: ${e.toString()}'));
    }
  }

  Future<void> importValidItems(List<ImportedItemModel> items) async {
    emit(ImportItemsSaving());
    try {
      final rows = items.map((e) => e.toInsertMap()).toList();
      final result = await _repo.bulkImportItems(rows);

      if (result is AppSuccess) {
        emit(ImportItemsDone(items.length));
      } else if (result is AppFailure) {
        emit(ImportItemsError(result.error.message));
      }
    } catch (e, st) {
      logger.e('importValidItems failed', error: e, stackTrace: st);
      emit(ImportItemsError('فشل الاستيراد: ${e.toString()}'));
    }
  }

  List<String> _validate(
    ImportedItemModel item,
    Set<String> existingSkus,
    Set<String> seenSkusInFile,
  ) {
    final errors = <String>[];

    if (item.name == null || item.name!.trim().isEmpty) {
      errors.add('الاسم مطلوب');
    }

    if (item.unit == null || item.unit!.trim().isEmpty) {
      errors.add('الوحدة مطلوبة');
    }

    if (item.rawQuantity == null || item.rawQuantity!.trim().isEmpty) {
      errors.add('الكمية مطلوبة');
    } else {
      final qty = int.tryParse(item.rawQuantity!.trim());
      if (qty == null) {
        errors.add('الكمية يجب أن تكون رقماً صحيحاً');
      } else if (qty < 0) {
        errors.add('الكمية لا يمكن أن تكون سالبة');
      }
    }

    if (item.rawAlarmLimit != null && item.rawAlarmLimit!.trim().isNotEmpty) {
      final limit = int.tryParse(item.rawAlarmLimit!.trim());
      if (limit == null) {
        errors.add('حد التنبيه يجب أن يكون رقماً');
      } else if (limit < 0) {
        errors.add('حد التنبيه لا يمكن أن يكون سالباً');
      }
    }

    if (item.sku != null && item.sku!.trim().isNotEmpty) {
      final skuLower = item.sku!.toLowerCase();
      if (seenSkusInFile.contains(skuLower)) {
        errors.add('الكود مكرر في الملف');
      } else if (existingSkus.contains(skuLower)) {
        errors.add('الكود موجود مسبقاً في قاعدة البيانات');
      }
    }

    return errors;
  }
}
