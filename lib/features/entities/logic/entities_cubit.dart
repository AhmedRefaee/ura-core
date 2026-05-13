import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/entity.dart';
import '../../verifier/data/entity_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class EntitiesState extends Equatable {
  const EntitiesState();
  @override
  List<Object?> get props => [];
}

class EntitiesInitial extends EntitiesState {}

class EntitiesLoading extends EntitiesState {}

class EntitiesLoaded extends EntitiesState {
  final List<Entity> all;
  final String query;
  final EntityCategory? categoryFilter;

  const EntitiesLoaded({
    required this.all,
    this.query = '',
    this.categoryFilter,
  });

  List<Entity> get filtered {
    var result = all;
    if (categoryFilter != null) {
      result = result.where((e) => e.category == categoryFilter).toList();
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  EntitiesLoaded copyWith({
    List<Entity>? all,
    String? query,
    EntityCategory? categoryFilter,
    bool? clearCategoryFilter,
  }) =>
      EntitiesLoaded(
        all: all ?? this.all,
        query: query ?? this.query,
        categoryFilter: clearCategoryFilter == true ? null : (categoryFilter ?? this.categoryFilter),
      );

  @override
  List<Object?> get props => [all, query, categoryFilter];
}

class EntitiesError extends EntitiesState {
  final String message;
  const EntitiesError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class EntitiesCubit extends Cubit<EntitiesState> {
  final EntityRepository _repo;

  EntitiesCubit(this._repo) : super(EntitiesInitial());

  Future<void> load() async {
    logger.d('EntitiesCubit → load');
    emit(EntitiesLoading());
    final result = await _repo.fetchEntities();
    switch (result) {
      case AppSuccess(:final data):
        emit(EntitiesLoaded(all: data));
        logger.i('EntitiesCubit → loaded ${data.length} entities');
      case AppFailure(:final error):
        logger.e('EntitiesCubit → load failed: ${error.message}');
        emit(EntitiesError(error.message));
    }
  }

  void search(String query) {
    final s = state;
    if (s is! EntitiesLoaded) return;
    emit(s.copyWith(query: query));
  }

  void filterByCategory(EntityCategory? category) {
    final s = state;
    if (s is! EntitiesLoaded) return;
    if (category == null) {
      emit(s.copyWith(clearCategoryFilter: true));
    } else {
      emit(s.copyWith(categoryFilter: category));
    }
  }

  /// Returns the error message if the operation failed, null on success.
  /// The UI should check the return value and display it if non-null.
  Future<String?> add({
    required String name,
    required EntityCategory category,
    String? contactName,
    String? contactPhone,
    String? address,
  }) async {
    logger.d('EntitiesCubit → add | $name');
    final result = await _repo.createEntity(
      name: name,
      category: category,
      contactName: contactName,
      contactPhone: contactPhone,
      address: address,
    );
    switch (result) {
      case AppSuccess():
        await load();
        return null;
      case AppFailure(:final error):
        logger.e('EntitiesCubit → add failed: ${error.message}');
        return error.message;
    }
  }

  Future<String?> edit({
    required String id,
    required String name,
    required EntityCategory category,
    String? contactName,
    String? contactPhone,
    String? address,
  }) async {
    logger.d('EntitiesCubit → edit | $id');
    final result = await _repo.updateEntity(
      id: id,
      name: name,
      category: category,
      contactName: contactName,
      contactPhone: contactPhone,
      address: address,
    );
    switch (result) {
      case AppSuccess():
        await load();
        return null;
      case AppFailure(:final error):
        logger.e('EntitiesCubit → edit failed: ${error.message}');
        return error.message;
    }
  }

  Future<String?> delete(String id) async {
    logger.d('EntitiesCubit → delete | $id');
    final result = await _repo.deleteEntity(id);
    switch (result) {
      case AppSuccess():
        await load();
        return null;
      case AppFailure(:final error):
        logger.e('EntitiesCubit → delete failed: ${error.message}');
        return error.message;
    }
  }
}
