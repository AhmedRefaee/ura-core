import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/project.dart';
import '../data/project_repository.dart';

part 'projects_state.dart';

class ProjectsCubit extends Cubit<ProjectsState> {
  final ProjectRepository _repo;
  ProjectsCubit(this._repo) : super(ProjectsInitial());

  Future<void> loadProjects(String entityId) async {
    try {
      emit(const ProjectsLoading());
      final result = await _repo.fetchProjectsForEntity(entityId);
      switch (result) {
        case AppSuccess(:final data):
          emit(ProjectsLoaded(data));
        case AppFailure(:final error):
          emit(ProjectsError(error.message));
      }
    } catch (e, st) {
      logger.e('ProjectsCubit → loadProjects failed', error: e, stackTrace: st);
      emit(const ProjectsError('حدث خطأ غير متوقع'));
    }
  }

  Future<void> createProject({
    required String entityId,
    required String name,
    String? letterheadImageUrl,
  }) async {
    try {
      final result = await _repo.createProject(
        entityId: entityId,
        name: name,
        letterheadImageUrl: letterheadImageUrl,
      );
      switch (result) {
        case AppSuccess(:final data):
          if (state is ProjectsLoaded) {
            final current = (state as ProjectsLoaded).projects;
            emit(ProjectsLoaded([data, ...current]));
          } else {
            emit(ProjectsLoaded([data]));
          }
        case AppFailure(:final error):
          emit(ProjectsError(error.message));
      }
    } catch (e, st) {
      logger.e('ProjectsCubit → createProject failed', error: e, stackTrace: st);
      emit(const ProjectsError('فشل إنشاء المشروع'));
    }
  }
}
