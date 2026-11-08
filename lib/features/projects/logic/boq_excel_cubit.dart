import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logic/safe_emit.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../../entities/logic/web_download_stub.dart'
    if (dart.library.html) '../../entities/logic/web_download_web.dart';
import '../data/project_repository.dart';
import 'boq_excel.dart';

/// The two Excel flows, the same split as the inventory's: a template adds new
/// lines, an export of the current lines updates them.
enum BoqExcelMode { add, update }

sealed class BoqExcelState {
  const BoqExcelState();
}

class BoqExcelIdle extends BoqExcelState {
  const BoqExcelIdle();
}

class BoqExcelBusy extends BoqExcelState {
  final String message;
  const BoqExcelBusy(this.message);
}

class BoqExcelParsed extends BoqExcelState {
  final BoqParseResult result;
  final String fileName;
  const BoqExcelParsed(this.result, this.fileName);
}

class BoqExcelSaving extends BoqExcelParsed {
  const BoqExcelSaving(super.result, super.fileName);
}

class BoqExcelApplied extends BoqExcelState {
  final int count;
  const BoqExcelApplied(this.count);
}

class BoqExcelError extends BoqExcelState {
  final String message;
  const BoqExcelError(this.message);
}

class BoqExcelCubit extends Cubit<BoqExcelState> with SafeEmit<BoqExcelState> {
  final ProjectRepository _repo;
  BoqExcelCubit(this._repo) : super(const BoqExcelIdle());

  /// Downloads the template, numbered to carry on after the project's lines.
  Future<void> downloadTemplate({required Project project, required String entityName}) async {
    safeEmit(const BoqExcelBusy('جارٍ إنشاء القالب...'));
    final current = await _fetchItems(project.id);
    if (current == null) return;
    try {
      final bytes = buildBoqTemplate(
        projectName: project.name,
        entityName: entityName,
        firstNumber: current.length + 1,
      );
      await _saveAndOpen(bytes, 'قالب_بنود_${_safeName(project.name)}.xlsx');
      safeEmit(const BoqExcelIdle());
    } catch (e, st) {
      logger.e('BoqExcelCubit → downloadTemplate failed', error: e, stackTrace: st);
      safeEmit(const BoqExcelError('فشل إنشاء القالب'));
    }
  }

  /// Downloads the project's current lines, ready to edit and upload.
  Future<void> exportForUpdate({required Project project, required String entityName}) async {
    safeEmit(const BoqExcelBusy('جارٍ تصدير البنود...'));
    final current = await _fetchItems(project.id);
    if (current == null) return;
    if (current.isEmpty) {
      safeEmit(const BoqExcelError('لا توجد بنود بعد. استخدم "إضافة بنود جديدة".'));
      return;
    }
    try {
      final bytes = buildBoqUpdateFile(projectName: project.name, entityName: entityName, items: current);
      await _saveAndOpen(bytes, 'تعديل_بنود_${_safeName(project.name)}.xlsx');
      safeEmit(const BoqExcelIdle());
    } catch (e, st) {
      logger.e('BoqExcelCubit → exportForUpdate failed', error: e, stackTrace: st);
      safeEmit(const BoqExcelError('فشل تصدير الملف'));
    }
  }

  /// Picks a file and parses it; the preview decides whether to go on. The
  /// lines are fetched fresh, since the file is checked against them.
  Future<void> pickAndParse(BoqExcelMode mode, String projectId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      safeEmit(const BoqExcelError('تعذر قراءة الملف'));
      return;
    }

    safeEmit(const BoqExcelBusy('جارٍ قراءة الملف...'));
    final current = await _fetchItems(projectId);
    if (current == null) return;
    try {
      final result = switch (mode) {
        BoqExcelMode.add => parseBoqTemplate(bytes, projectId: projectId, existing: current),
        BoqExcelMode.update => parseBoqUpdateFile(bytes, current: current),
      };
      if (result.fileError != null) {
        safeEmit(BoqExcelError(result.fileError!));
      } else if (result.totalRows == 0) {
        safeEmit(const BoqExcelError('لم يتم العثور على صفوف بيانات في الملف'));
      } else {
        safeEmit(BoqExcelParsed(result, file.name));
      }
    } catch (e, st) {
      logger.e('BoqExcelCubit → parse failed', error: e, stackTrace: st);
      safeEmit(const BoqExcelError('الملف غير صالح أو تالف'));
    }
  }

  /// Applies the file's good rows. Rows with errors are skipped: nothing gets
  /// deleted here, so a skipped row just stays as it was.
  Future<void> apply(String projectId) async {
    final current = state;
    if (current is! BoqExcelParsed || current is BoqExcelSaving || !current.result.canApply) return;
    safeEmit(BoqExcelSaving(current.result, current.fileName));
    final saved = await _repo.applyProjectItems(
      projectId,
      current.result.items,
      rowNumbers: current.result.rowNumbers,
    );
    switch (saved) {
      case AppSuccess(:final data):
        safeEmit(BoqExcelApplied(data));
      case AppFailure(:final error):
        safeEmit(BoqExcelError(error.message));
    }
  }

  void reset() => safeEmit(const BoqExcelIdle());

  /// Null when it failed, with the error already emitted.
  Future<List<ProjectItem>?> _fetchItems(String projectId) async {
    final result = await _repo.fetchProjectItems(projectId);
    switch (result) {
      case AppSuccess(:final data):
        return data;
      case AppFailure(:final error):
        safeEmit(BoqExcelError(error.message));
        return null;
    }
  }

  Future<void> _saveAndOpen(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      triggerWebDownload(bytes, fileName);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    final opened = await OpenFilex.open(file.path);
    if (opened.type != ResultType.done) {
      logger.w('open_filex: ${opened.type} — ${opened.message}');
    }
  }

  static String _safeName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
