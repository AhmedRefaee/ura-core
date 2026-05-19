import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/inventory_management_repository.dart';
import '../data/models/bulk_edit_error_model.dart';
import '../data/models/bulk_edit_item_model.dart';
import 'bulk_edit_excel_state.dart';
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';

class BulkEditExcelCubit extends Cubit<BulkEditExcelState> {
  final InventoryManagementRepository _repo;

  BulkEditExcelCubit(this._repo) : super(BulkEditExcelInitial());

  Future<void> exportCurrentItems() async {
    emit(BulkEditExcelExporting());
    try {
      final result = await _repo.fetchAllForExport();
      if (result is AppFailure) {
        emit(BulkEditExcelError((result as AppFailure<List<InventoryItem>>).error.message));
        return;
      }
      final items = (result as AppSuccess<List<InventoryItem>>).data;
      final bytes = _buildExportBytes(items);
      if (bytes == null) {
        emit(BulkEditExcelError('فشل إنشاء ملف Excel'));
        return;
      }

      if (kIsWeb) {
        triggerWebDownload(bytes, 'تعديل_المخزون.xlsx');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/تعديل_المخزون.xlsx');
        await file.writeAsBytes(bytes);
        final openResult = await OpenFilex.open(file.path);
        if (openResult.type != ResultType.done) {
          logger.w('open_filex: ${openResult.type} — ${openResult.message}');
        }
      }
      emit(BulkEditExcelInitial());
    } catch (e, st) {
      logger.e('exportCurrentItems failed', error: e, stackTrace: st);
      emit(BulkEditExcelError('فشل التصدير: ${e.toString()}'));
    }
  }

  List<int>? _buildExportBytes(List<InventoryItem> items) {
    final excel = Excel.createExcel();
    final sheet = excel['المخزون'];
    excel.delete('Sheet1');

    final headers = [
      'الرقم التعريفي (لا تعدل)',
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
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(bold: true);
    }

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final rowIndex = i + 1;

      void setStr(int col, String? value) {
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: col, rowIndex: rowIndex))
            .value = TextCellValue(value ?? '');
      }

      void setInt(int col, int value) {
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: col, rowIndex: rowIndex))
            .value = IntCellValue(value);
      }

      setStr(0, item.id);
      setStr(1, item.itemName);
      setStr(2, item.unit);
      setInt(3, item.quantity);
      setStr(4, item.sku);
      setStr(5, item.category);
      setInt(6, item.minQuantity);
      setStr(7, item.description);
      setStr(8, item.notes);
    }

    return excel.encode();
  }

  Future<void> pickAndParseBulkEdit() async {
    emit(BulkEditExcelParsing());
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        emit(BulkEditExcelInitial());
        return;
      }

      final bytes = picked.files.first.bytes;
      if (bytes == null) {
        emit(BulkEditExcelError('تعذر قراءة الملف'));
        return;
      }

      final allResult = await _repo.fetchAllForExport();
      Set<String> existingIds = {};
      if (allResult is AppSuccess<List<InventoryItem>>) {
        existingIds = allResult.data.map((e) => e.id.toLowerCase()).toSet();
      }

      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        emit(BulkEditExcelError('الملف فارغ أو لا يحتوي على بيانات'));
        return;
      }

      final validItems = <BulkEditItemModel>[];
      final invalidItems = <BulkEditErrorModel>[];
      final seenIds = <String>{};
      int totalRows = 0;

      // Skip row 0 (header)
      for (var rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
        final row = sheet.rows[rowIdx];

        String? cellStr(int col) {
          if (col >= row.length) return null;
          final v = row[col]?.value;
          if (v == null) return null;
          final s = v.toString().trim();
          return s.isEmpty ? null : s;
        }

        final item = BulkEditItemModel(
          rowNumber: rowIdx + 1,
          id: cellStr(0),
          name: cellStr(1),
          unit: cellStr(2),
          rawQuantity: cellStr(3),
          sku: cellStr(4),
          category: cellStr(5),
          rawAlarmLimit: cellStr(6),
          description: cellStr(7),
          notes: cellStr(8),
        );

        if (item.isEmpty) continue;
        totalRows++;

        final errors = _validate(item, existingIds, seenIds);
        if (errors.isEmpty) {
          seenIds.add(item.id!.toLowerCase());
          validItems.add(item);
        } else {
          invalidItems.add(BulkEditErrorModel(
            rowNumber: item.rowNumber,
            errors: errors,
            rawData: item,
          ));
        }
      }

      if (totalRows == 0) {
        emit(BulkEditExcelError('لم يتم العثور على صفوف بيانات في الملف'));
        return;
      }

      emit(BulkEditExcelParsed(
        validItems: validItems,
        invalidItems: invalidItems,
        totalRows: totalRows,
      ));
    } catch (e, st) {
      logger.e('pickAndParseBulkEdit failed', error: e, stackTrace: st);
      emit(BulkEditExcelError('فشل تحليل الملف: ${e.toString()}'));
    }
  }

  Future<void> applyUpdates(List<BulkEditItemModel> items) async {
    emit(BulkEditExcelSaving());
    try {
      final rows = items.map((e) => e.toUpdateMap()).toList();
      final result = await _repo.bulkUpdateItems(rows);
      if (result is AppSuccess) {
        emit(BulkEditExcelDone(items.length));
      } else if (result is AppFailure) {
        emit(BulkEditExcelError(
            (result as AppFailure<void>).error.message));
      }
    } catch (e, st) {
      logger.e('applyUpdates failed', error: e, stackTrace: st);
      emit(BulkEditExcelError('فشل التحديث: ${e.toString()}'));
    }
  }

  List<String> _validate(
    BulkEditItemModel item,
    Set<String> existingIds,
    Set<String> seenIds,
  ) {
    final errors = <String>[];

    if (item.id == null || item.id!.trim().isEmpty) {
      errors.add('الرقم التعريفي مفقود، لا يمكن التحديث');
      return errors;
    }

    final idLower = item.id!.toLowerCase();
    if (seenIds.contains(idLower)) {
      errors.add('الرقم التعريفي مكرر في الملف');
    } else if (!existingIds.contains(idLower)) {
      errors.add('لم يتم العثور على عنصر بهذا المعرف');
    }

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

    return errors;
  }
}
