import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/project.dart';
import '../data/project_repository.dart';
import '../data/project_storage_service.dart';

part 'projects_state.dart';

/// A picked letterhead image, ready to upload.
class LetterheadImage {
  final Uint8List bytes;
  final String extension;
  final String mimeType;
  const LetterheadImage({required this.bytes, required this.extension, required this.mimeType});
}

class ProjectsCubit extends Cubit<ProjectsState> {
  final ProjectRepository _repo;
  final ProjectStorageService _storage;
  ProjectsCubit(this._repo, this._storage) : super(const ProjectsInitial());

  Future<void> loadProjects(String entityId) async {
    emit(const ProjectsLoading());
    final result = await _repo.fetchProjectsForEntity(entityId);
    switch (result) {
      case AppSuccess(:final data):
        emit(ProjectsLoaded(data));
      case AppFailure(:final error):
        emit(ProjectsError(error.message));
    }
  }

  /// Returns an error message, or null on success. The letterhead is uploaded
  /// after the row exists because its storage path is keyed by project id.
  Future<String?> createProject({
    required String entityId,
    required String name,
    LetterheadImage? letterhead,
  }) async {
    final created = await _repo.createProject(entityId: entityId, name: name);
    Project project;
    switch (created) {
      case AppSuccess(:final data):
        project = data;
      case AppFailure(:final error):
        return error.message;
    }

    String? warning;
    if (letterhead != null) {
      final upload = await _storage.uploadLetterhead(
        projectId: project.id,
        bytes: letterhead.bytes,
        fileExtension: letterhead.extension,
        mimeType: letterhead.mimeType,
      );
      switch (upload) {
        case AppSuccess(:final data):
          final updated = await _repo.updateProject(id: project.id, letterheadImageUrl: data);
          if (updated case AppSuccess(:final data)) project = data;
        case AppFailure():
          warning = 'تم إنشاء المشروع لكن تعذر رفع الترويسة';
      }
    }

    final current = state is ProjectsLoaded ? (state as ProjectsLoaded).projects : const <Project>[];
    emit(ProjectsLoaded([project, ...current]));
    return warning;
  }
}
