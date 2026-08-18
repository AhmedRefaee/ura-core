import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/order_template.dart';
import '../../verifier/data/entity_repository.dart';
import '../../verifier/data/order_template_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ── States ────────────────────────────────────────────────────────────────────

class TemplateEntityGroup extends Equatable {
  final String entityId;
  final String entityName;
  final List<OrderTemplate> templates;

  const TemplateEntityGroup({
    required this.entityId,
    required this.entityName,
    required this.templates,
  });

  int get count => templates.length;

  @override
  List<Object?> get props => [entityId, entityName, templates];
}

abstract class TemplateManagementState extends Equatable {
  const TemplateManagementState();
  @override
  List<Object?> get props => [];
}

class TemplateManagementInitial extends TemplateManagementState {}

class TemplateManagementLoading extends TemplateManagementState {}

class TemplateManagementLoaded extends TemplateManagementState {
  final List<OrderTemplate> templates;
  final List<Entity> entities;
  final String query;

  /// Set when arriving from the create-order picker: the matching group is
  /// expanded and scrolled to once, then cleared via [clearFocus].
  final String? focusEntityId;

  const TemplateManagementLoaded({
    required this.templates,
    required this.entities,
    this.query = '',
    this.focusEntityId,
  });

  List<TemplateEntityGroup> get groups {
    final byEntity = <String, List<OrderTemplate>>{};
    for (final template in templates) {
      byEntity.putIfAbsent(template.entityId, () => []).add(template);
    }

    final q = query.trim().toLowerCase();
    final result = <TemplateEntityGroup>[];
    byEntity.forEach((entityId, entityTemplates) {
      final matches = entities.where((e) => e.id == entityId);
      // entity_id is ON DELETE CASCADE, so an orphan shouldn't be reachable.
      final entityName = matches.isEmpty ? 'بدون جهة' : matches.first.name;
      if (q.isNotEmpty) {
        final hit =
            entityName.toLowerCase().contains(q) ||
            entityTemplates.any(
              (t) =>
                  t.displayTitle.toLowerCase().contains(q) ||
                  t.itemsSummary.toLowerCase().contains(q),
            );
        if (!hit) return;
      }
      result.add(
        TemplateEntityGroup(
          entityId: entityId,
          entityName: entityName,
          templates: entityTemplates,
        ),
      );
    });

    result.sort((a, b) => a.entityName.compareTo(b.entityName));
    return result;
  }

  TemplateManagementLoaded copyWith({
    List<OrderTemplate>? templates,
    List<Entity>? entities,
    String? query,
    String? focusEntityId,
    bool clearFocus = false,
  }) => TemplateManagementLoaded(
    templates: templates ?? this.templates,
    entities: entities ?? this.entities,
    query: query ?? this.query,
    focusEntityId: clearFocus ? null : (focusEntityId ?? this.focusEntityId),
  );

  @override
  List<Object?> get props => [templates, entities, query, focusEntityId];
}

class TemplateManagementError extends TemplateManagementState {
  final String message;
  const TemplateManagementError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class TemplateManagementCubit extends Cubit<TemplateManagementState>
    with SafeEmit<TemplateManagementState> {
  final OrderTemplateRepository _templateRepo;
  final EntityRepository _entityRepo;

  TemplateManagementCubit(this._templateRepo, this._entityRepo)
    : super(TemplateManagementInitial());

  Future<void> load({String? focusEntityId}) async {
    logger.d('TemplateManagementCubit → load');
    safeEmit(TemplateManagementLoading());

    final results = await Future.wait([
      _templateRepo.fetchAll(),
      _entityRepo.fetchEntities(),
    ]);
    if (isClosed) return;

    final templatesResult = results[0] as AppResult<List<OrderTemplate>>;
    final entitiesResult = results[1] as AppResult<List<Entity>>;

    final templatesError = templatesResult.failureOrNull;
    if (templatesError != null) {
      logger.e('TemplateManagementCubit → load failed: ${templatesError.message}');
      safeEmit(TemplateManagementError(templatesError.message));
      return;
    }
    final entitiesError = entitiesResult.failureOrNull;
    if (entitiesError != null) {
      logger.e('TemplateManagementCubit → load failed: ${entitiesError.message}');
      safeEmit(TemplateManagementError(entitiesError.message));
      return;
    }

    final templates = (templatesResult as AppSuccess<List<OrderTemplate>>).data;
    safeEmit(
      TemplateManagementLoaded(
        templates: templates,
        entities: (entitiesResult as AppSuccess<List<Entity>>).data,
        focusEntityId: focusEntityId,
      ),
    );
    logger.i('TemplateManagementCubit → loaded ${templates.length} templates');
  }

  void search(String query) {
    final s = state;
    if (s is! TemplateManagementLoaded) return;
    safeEmit(s.copyWith(query: query));
  }

  void clearFocus() {
    final s = state;
    if (s is! TemplateManagementLoaded) return;
    safeEmit(s.copyWith(clearFocus: true));
  }

  Future<void> delete(String templateId) async {
    final s = state;
    if (s is! TemplateManagementLoaded) return;
    final optimistic = s.templates.where((t) => t.id != templateId).toList();
    safeEmit(s.copyWith(templates: optimistic));
    final result = await _templateRepo.deleteTemplate(templateId);
    if (isClosed) return;
    switch (result) {
      case AppSuccess():
        logger.i('TemplateManagementCubit → deleted $templateId');
      case AppFailure(:final error):
        logger.e('TemplateManagementCubit → delete failed: ${error.message}');
        safeEmit(s); // restore original list on failure
    }
  }
}
