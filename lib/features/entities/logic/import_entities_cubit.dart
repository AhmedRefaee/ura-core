import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/entity.dart';
import '../../verifier/data/entity_repository.dart';
import '../data/models/imported_entity_model.dart';
import '../data/models/entity_import_error_model.dart';
import 'import_entities_state.dart';
import '../../../core/logic/safe_emit.dart';
import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';

class ImportEntitiesCubit extends Cubit<ImportEntitiesState>
    with SafeEmit<ImportEntitiesState> {
  final EntityRepository _repo;

  ImportEntitiesCubit(this._repo) : super(ImportEntitiesInitial());

  Future<void> exportEntities() async {
    safeEmit(ImportEntitiesExporting());
    try {
      final result = await _repo.fetchEntities();
      final List<Entity> entities;
      switch (result) {
        case AppSuccess(:final data):
          entities = data;
        case AppFailure(:final error):
          safeEmit(ImportEntitiesError('فشل تحميل البيانات: ${error.message}'));
          return;
      }
      final bytes = _buildExportBytes(entities);
      if (bytes == null) {
        safeEmit(ImportEntitiesError('فشل إنشاء الملف'));
        return;
      }

      if (kIsWeb) {
        triggerWebDownload(bytes, 'الجهات.xlsx');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/الجهات.xlsx');
        await file.writeAsBytes(bytes);
        final openResult = await OpenFilex.open(file.path);
        if (openResult.type != ResultType.done) {
          logger.w('open_filex: ${openResult.type} — ${openResult.message}');
        }
      }

      safeEmit(ImportEntitiesInitial());
    } catch (e, st) {
      logger.e('exportEntities failed', error: e, stackTrace: st);
      safeEmit(ImportEntitiesError('فشل التصدير: ${e.toString()}'));
    }
  }

  List<int>? _buildExportBytes(List<Entity> entities) {
    final excel = Excel.createExcel();
    final sheet = excel['الجهات'];
    excel.delete('Sheet1');

    final headers = [
      'الرقم التعريفي',
      'الاسم *',
      'التصنيف *',
      'اسم جهة الاتصال',
      'رقم الهاتف',
      'العنوان',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(bold: true);
    }

    for (var rowIdx = 0; rowIdx < entities.length; rowIdx++) {
      final e = entities[rowIdx];
      final row = [
        e.id,
        e.name,
        e.category.label,
        e.contactName ?? '',
        e.contactPhone ?? '',
        e.address ?? '',
      ];
      for (var col = 0; col < row.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx + 1),
        );
        cell.value = TextCellValue(row[col]);
      }
    }

    return excel.encode();
  }

  Future<void> pickAndParse() async {
    safeEmit(ImportEntitiesParsing());
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        safeEmit(ImportEntitiesInitial());
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        safeEmit(ImportEntitiesError('تعذر قراءة الملف'));
        return;
      }

      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        safeEmit(ImportEntitiesError('الملف فارغ أو لا يحتوي على بيانات'));
        return;
      }

      final validItems = <ImportedEntityModel>[];
      final invalidItems = <EntityImportErrorModel>[];
      final seenNamesInFile = <String>{};
      int totalRows = 0;

      // Skip row 0 (header), start from row 1
      for (var rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
        final row = sheet.rows[rowIdx];

        String? cellStr(int col) {
          if (col >= row.length) return null;
          final v = row[col]?.value;
          if (v == null) return null;
          final s = v.toString().trim();
          return s.isEmpty ? null : s;
        }

        final item = ImportedEntityModel(
          rowNumber: rowIdx + 1,
          id: cellStr(0),
          name: cellStr(1),
          rawCategory: cellStr(2),
          contactName: cellStr(3),
          contactPhone: cellStr(4),
          address: cellStr(5),
        );

        if (item.isEmpty) continue;
        totalRows++;

        final errors = _validate(item, seenNamesInFile);
        if (errors.isEmpty) {
          // Track in-file name duplicates only for new rows
          if (!item.isExistingRow && item.name != null) {
            seenNamesInFile.add(item.name!.toLowerCase());
          }
          validItems.add(item);
        } else {
          invalidItems.add(
            EntityImportErrorModel(
              rowNumber: item.rowNumber,
              errors: errors,
              rawData: item,
            ),
          );
        }
      }

      if (totalRows == 0) {
        safeEmit(ImportEntitiesError('لم يتم العثور على صفوف بيانات في الملف'));
        return;
      }

      safeEmit(
        ImportEntitiesParsed(
          validItems: validItems,
          invalidItems: invalidItems,
          totalRows: totalRows,
        ),
      );
    } catch (e, st) {
      logger.e('pickAndParse failed', error: e, stackTrace: st);
      safeEmit(ImportEntitiesError('فشل تحليل الملف: ${e.toString()}'));
    }
  }

  Future<void> applyChanges(List<ImportedEntityModel> items) async {
    safeEmit(ImportEntitiesSaving());
    try {
      final updatedCount = items.where((e) => e.isExistingRow).length;
      final insertedCount = items.where((e) => !e.isExistingRow).length;

      final rows = items.map((e) => e.toUpsertMap()).toList();
      final result = await _repo.upsertEntities(rows);
      switch (result) {
        case AppSuccess():
          safeEmit(
            ImportEntitiesDone(
              updatedCount: updatedCount,
              insertedCount: insertedCount,
            ),
          );
        case AppFailure(:final error):
          safeEmit(ImportEntitiesError(error.message));
      }
    } catch (e, st) {
      logger.e('applyChanges failed', error: e, stackTrace: st);
      safeEmit(ImportEntitiesError('فشل تطبيق التغييرات: ${e.toString()}'));
    }
  }

  List<String> _validate(
    ImportedEntityModel item,
    Set<String> seenNamesInFile,
  ) {
    final errors = <String>[];

    if (item.name == null || item.name!.trim().isEmpty) {
      errors.add('الاسم مطلوب');
    } else if (!item.isExistingRow) {
      // Only check in-file name duplicates for new rows
      final nameLower = item.name!.toLowerCase();
      if (seenNamesInFile.contains(nameLower)) {
        errors.add('الاسم مكرر في الملف');
      }
    }

    if (item.rawCategory == null || item.rawCategory!.trim().isEmpty) {
      errors.add('التصنيف مطلوب');
    } else {
      final cat = item.rawCategory!.trim();
      if (cat != 'وارد' && cat != 'صادر' && cat != 'غير محدد') {
        errors.add('التصنيف يجب أن يكون: وارد أو صادر أو غير محدد');
      }
    }

    return errors;
  }
}
