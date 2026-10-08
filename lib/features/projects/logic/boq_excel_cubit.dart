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

class BoqExcelImported extends BoqExcelState {
  final int count;
  const BoqExcelImported(this.count);
}

class BoqExcelError extends BoqExcelState {
  final String message;
  const BoqExcelError(this.message);
}

class BoqExcelCubit extends Cubit<BoqExcelState> with SafeEmit<BoqExcelState> {
  final ProjectRepository _repo;
  BoqExcelCubit(this._repo) : super(const BoqExcelIdle());

  Future<void> export({required Project project, required String entityName, required List<ProjectItem> items}) async {
    safeEmit(const BoqExcelBusy('جارٍ إنشاء الملف...'));
    try {
      final bytes = buildBoqWorkbook(projectName: project.name, entityName: entityName, items: items);
      final fileName = 'بنود_${project.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.xlsx';
      if (kIsWeb) {
        triggerWebDownload(bytes, fileName);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        final opened = await OpenFilex.open(file.path);
        if (opened.type != ResultType.done) {
          logger.w('open_filex: ${opened.type} — ${opened.message}');
        }
      }
      safeEmit(const BoqExcelIdle());
    } catch (e, st) {
      logger.e('BoqExcelCubit → export failed', error: e, stackTrace: st);
      safeEmit(const BoqExcelError('فشل تصدير الملف'));
    }
  }

  /// Picks a file and parses it; the preview decides whether to go on.
  Future<void> pickAndParse(String projectId) async {
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
    try {
      final result = parseBoqWorkbook(bytes, projectId: projectId);
      if (result.noHeaderFound) {
        safeEmit(const BoqExcelError('لم يتم العثور على جدول بنود (عمود "البند") في الملف'));
        return;
      }
      safeEmit(BoqExcelParsed(result, file.name));
    } catch (e, st) {
      logger.e('BoqExcelCubit → parse failed', error: e, stackTrace: st);
      safeEmit(const BoqExcelError('الملف غير صالح أو تالف'));
    }
  }

  /// Replaces the whole quotation. Refuses while the file has bad rows:
  /// with replace semantics, skipping them would silently delete lines.
  Future<void> confirmReplace(String projectId) async {
    final current = state;
    if (current is! BoqExcelParsed || current is BoqExcelSaving || !current.result.canImport) return;
    safeEmit(BoqExcelSaving(current.result, current.fileName));
    final saved = await _repo.replaceProjectItems(projectId, current.result.items);
    switch (saved) {
      case AppSuccess(:final data):
        safeEmit(BoqExcelImported(data));
      case AppFailure(:final error):
        safeEmit(BoqExcelError(error.message));
    }
  }

  void reset() => safeEmit(const BoqExcelIdle());
}
