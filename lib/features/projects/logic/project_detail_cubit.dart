import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../data/project_repository.dart';
import '../data/project_storage_service.dart';
import 'projects_cubit.dart';

class ProjectDetailState extends Equatable {
  final Project project;
  final bool loading;
  final List<ProjectItem> items;

  /// Whether this user may see and edit quotation pricing -- decided by the
  /// server's project_item_pricing_visible(), never by a local role check.
  final bool canEditItems;
  final String? error;

  const ProjectDetailState({
    required this.project,
    this.loading = false,
    this.items = const [],
    this.canEditItems = false,
    this.error,
  });

  double get quotationTotal => items.fold(0, (sum, i) => sum + (i.totalPrice ?? 0));

  ProjectDetailState copyWith({
    Project? project,
    bool? loading,
    List<ProjectItem>? items,
    bool? canEditItems,
    String? error,
  }) =>
      ProjectDetailState(
        project: project ?? this.project,
        loading: loading ?? this.loading,
        items: items ?? this.items,
        canEditItems: canEditItems ?? this.canEditItems,
        error: error,
      );

  @override
  List<Object?> get props => [project, loading, items, canEditItems, error];
}

class ProjectDetailCubit extends Cubit<ProjectDetailState> {
  final ProjectRepository _repo;
  final ProjectStorageService _storage;

  ProjectDetailCubit(this._repo, this._storage, Project project)
      : super(ProjectDetailState(project: project));

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final results = await Future.wait([
      _repo.fetchProjectItems(state.project.id),
      _repo.canEditPricing(),
    ]);
    final items = results[0] as AppResult<List<ProjectItem>>;
    final canEdit = results[1] as AppResult<bool>;
    switch (items) {
      case AppSuccess(:final data):
        emit(state.copyWith(
          loading: false,
          items: data,
          canEditItems: canEdit is AppSuccess<bool> && canEdit.data,
        ));
      case AppFailure(:final error):
        emit(state.copyWith(loading: false, error: error.message));
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> saveItem(ProjectItem item) async {
    final result = item.id.isEmpty
        ? await _repo.createProjectItem(item)
        : await _repo.updateProjectItem(item);
    switch (result) {
      case AppSuccess():
        await load();
        return null;
      case AppFailure(:final error):
        return error.message;
    }
  }

  Future<String?> deleteItem(String id) async {
    final result = await _repo.deleteProjectItem(id);
    switch (result) {
      case AppSuccess():
        emit(state.copyWith(items: state.items.where((i) => i.id != id).toList()));
        return null;
      case AppFailure(:final error):
        return error.message;
    }
  }

  Future<String?> replaceLetterhead(LetterheadImage image) async {
    final upload = await _storage.uploadLetterhead(
      projectId: state.project.id,
      bytes: image.bytes,
      fileExtension: image.extension,
      mimeType: image.mimeType,
    );
    switch (upload) {
      case AppSuccess(:final data):
        final updated = await _repo.updateProject(id: state.project.id, letterheadImageUrl: data);
        switch (updated) {
          case AppSuccess(:final data):
            emit(state.copyWith(project: data));
            return null;
          case AppFailure(:final error):
            return error.message;
        }
      case AppFailure(:final error):
        return error.message;
    }
  }
}
