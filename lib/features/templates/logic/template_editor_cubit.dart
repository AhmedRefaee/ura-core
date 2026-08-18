import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/draft_order_item.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_template.dart';
import '../../../shared/models/profile.dart';
import '../../verifier/data/entity_repository.dart';
import '../../verifier/data/inventory_repository.dart';
import '../../verifier/data/order_repository.dart';
import '../../verifier/data/order_template_repository.dart';

import '../../../core/logic/safe_emit.dart';
export '../../../shared/models/draft_order_item.dart' show DraftOrderItem;

// ── States ────────────────────────────────────────────────────────────────────

abstract class TemplateEditorState extends Equatable {
  const TemplateEditorState();
  @override
  List<Object?> get props => [];
}

class TemplateEditorInitial extends TemplateEditorState {}

class TemplateEditorLoadingLookups extends TemplateEditorState {}

class TemplateEditorLoadError extends TemplateEditorState {
  final String message;
  const TemplateEditorLoadError(this.message);
  @override
  List<Object?> get props => [message];
}

class TemplateEditorReady extends TemplateEditorState {
  /// null while creating; non-null when editing an existing template.
  final String? id;
  final List<Entity> entities;
  final List<Profile> reps;
  final List<InventoryItem> inventory;
  final OrderDirection direction;
  final Entity? selectedEntity;
  final Profile? selectedRep;
  final List<DraftOrderItem> items;
  final String? notes;
  final String? name;
  final String? description;
  final bool isSaving;
  final bool isDeleting;
  final bool justSaved;
  final bool justDeleted;
  final String? actionError;

  const TemplateEditorReady({
    this.id,
    required this.entities,
    required this.reps,
    required this.inventory,
    required this.direction,
    this.selectedEntity,
    this.selectedRep,
    this.items = const [],
    this.notes,
    this.name,
    this.description,
    this.isSaving = false,
    this.isDeleting = false,
    this.justSaved = false,
    this.justDeleted = false,
    this.actionError,
  });

  bool get isNew => id == null;

  bool get canSave =>
      selectedEntity != null &&
      items.isNotEmpty &&
      (direction == OrderDirection.inboundExternal || selectedRep != null);

  /// [justSaved], [justDeleted] and [actionError] are one-shot: they are not
  /// carried forward, so the screen's listener fires once per occurrence.
  TemplateEditorReady copyWith({
    OrderDirection? direction,
    Entity? selectedEntity,
    bool clearEntity = false,
    Profile? selectedRep,
    bool clearRep = false,
    List<DraftOrderItem>? items,
    String? notes,
    bool clearNotes = false,
    String? name,
    bool clearName = false,
    String? description,
    bool clearDescription = false,
    bool? isSaving,
    bool? isDeleting,
    bool justSaved = false,
    bool justDeleted = false,
    String? actionError,
  }) {
    return TemplateEditorReady(
      id: id,
      entities: entities,
      reps: reps,
      inventory: inventory,
      direction: direction ?? this.direction,
      selectedEntity: clearEntity
          ? null
          : (selectedEntity ?? this.selectedEntity),
      selectedRep: clearRep ? null : (selectedRep ?? this.selectedRep),
      items: items ?? this.items,
      notes: clearNotes ? null : (notes ?? this.notes),
      name: clearName ? null : (name ?? this.name),
      description: clearDescription
          ? null
          : (description ?? this.description),
      isSaving: isSaving ?? this.isSaving,
      isDeleting: isDeleting ?? this.isDeleting,
      justSaved: justSaved,
      justDeleted: justDeleted,
      actionError: actionError,
    );
  }

  @override
  List<Object?> get props => [
    id,
    entities,
    reps,
    inventory,
    direction,
    selectedEntity,
    selectedRep,
    items,
    notes,
    name,
    description,
    isSaving,
    isDeleting,
    justSaved,
    justDeleted,
    actionError,
  ];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class TemplateEditorCubit extends Cubit<TemplateEditorState>
    with SafeEmit<TemplateEditorState> {
  final EntityRepository _entityRepo;
  final OrderRepository _orderRepo;
  final InventoryRepository _inventoryRepo;
  final OrderTemplateRepository _templateRepo;

  /// null = create mode.
  final OrderTemplate? _initial;

  TemplateEditorCubit(
    this._entityRepo,
    this._orderRepo,
    this._inventoryRepo,
    this._templateRepo,
    this._initial,
  ) : super(TemplateEditorInitial());

  Future<void> loadLookups() async {
    logger.d('TemplateEditorCubit → loadLookups');
    safeEmit(TemplateEditorLoadingLookups());

    final results = await Future.wait([
      _entityRepo.fetchEntities(),
      _orderRepo.fetchReps(),
      _inventoryRepo.fetchInventory(),
    ]);
    if (isClosed) return;

    final entitiesResult = results[0] as AppResult<List<Entity>>;
    final repsResult = results[1] as AppResult<List<Profile>>;
    final inventoryResult = results[2] as AppResult<List<InventoryItem>>;

    for (final result in [entitiesResult, repsResult, inventoryResult]) {
      final error = result.failureOrNull;
      if (error != null) {
        logger.e('TemplateEditorCubit → loadLookups failed: ${error.message}');
        safeEmit(TemplateEditorLoadError(error.message));
        return;
      }
    }

    final entities = (entitiesResult as AppSuccess<List<Entity>>).data;
    final reps = (repsResult as AppSuccess<List<Profile>>).data;
    final inventory = (inventoryResult as AppSuccess<List<InventoryItem>>).data;

    final initial = _initial;
    if (initial == null) {
      safeEmit(
        TemplateEditorReady(
          entities: entities,
          reps: reps,
          inventory: inventory,
          direction: OrderDirection.outbound,
        ),
      );
      logger.i('TemplateEditorCubit → ready (create mode)');
      return;
    }

    final entityMatches = entities.where((e) => e.id == initial.entityId);
    final repMatches = initial.repId == null
        ? const <Profile>[]
        : reps.where((r) => r.id == initial.repId);

    safeEmit(
      TemplateEditorReady(
        id: initial.id,
        entities: entities,
        reps: reps,
        inventory: inventory,
        direction: initial.direction,
        selectedEntity: entityMatches.isEmpty ? null : entityMatches.first,
        selectedRep: repMatches.isEmpty ? null : repMatches.first,
        items: initial.items
            .map(
              (i) => DraftOrderItem(
                inventoryId: i.inventoryId,
                inventoryName: i.inventoryName,
                quantity: i.quantity,
                isCustom: i.isCustom,
                customDescription: i.customDescription,
                sourceInventoryId: i.sourceInventoryId,
              ),
            )
            .toList(),
        notes: initial.notes,
        name: initial.name,
        description: initial.description,
      ),
    );
    logger.i('TemplateEditorCubit → ready (editing ${initial.id})');
  }

  void selectEntity(Entity entity) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    safeEmit(s.copyWith(selectedEntity: entity));
  }

  void selectRep(Profile rep) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    safeEmit(s.copyWith(selectedRep: rep));
  }

  void setDirection(OrderDirection direction) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    safeEmit(
      s.copyWith(
        direction: direction,
        clearRep: direction == OrderDirection.inboundExternal,
      ),
    );
  }

  void addInventoryItem(InventoryItem item, double quantity) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final updated = List<DraftOrderItem>.from(s.items)
      ..add(
        DraftOrderItem(
          inventoryId: item.id,
          inventoryName: item.itemName,
          quantity: quantity,
          isCustom: false,
        ),
      );
    safeEmit(s.copyWith(items: updated));
  }

  void addCustomItem(
    String description,
    double quantity, {
    String? sourceInventoryId,
  }) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final updated = List<DraftOrderItem>.from(s.items)
      ..add(
        DraftOrderItem(
          quantity: quantity,
          isCustom: true,
          customDescription: description,
          sourceInventoryId: sourceInventoryId,
        ),
      );
    safeEmit(s.copyWith(items: updated));
  }

  void addMultipleItems(
    List<({InventoryItem item, double quantity})> itemsWithQuantities,
  ) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final updated = List<DraftOrderItem>.from(s.items);
    for (final entry in itemsWithQuantities) {
      updated.add(
        DraftOrderItem(
          inventoryId: entry.item.id,
          inventoryName: entry.item.itemName,
          quantity: entry.quantity,
          isCustom: false,
        ),
      );
    }
    safeEmit(s.copyWith(items: updated));
  }

  void removeItem(int index) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final updated = List<DraftOrderItem>.from(s.items)..removeAt(index);
    safeEmit(s.copyWith(items: updated));
  }

  void setNotes(String notes) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final trimmed = notes.trim();
    safeEmit(s.copyWith(notes: notes, clearNotes: trimmed.isEmpty));
  }

  void setName(String name) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final trimmed = name.trim();
    safeEmit(s.copyWith(name: name, clearName: trimmed.isEmpty));
  }

  void setDescription(String description) {
    final s = state;
    if (s is! TemplateEditorReady) return;
    final trimmed = description.trim();
    safeEmit(
      s.copyWith(description: description, clearDescription: trimmed.isEmpty),
    );
  }

  Future<void> save() async {
    final s = state;
    if (s is! TemplateEditorReady || !s.canSave) return;
    logger.d('TemplateEditorCubit → save');
    safeEmit(s.copyWith(isSaving: true));

    final result = s.isNew
        ? await _templateRepo.createTemplate(
            entityId: s.selectedEntity!.id,
            direction: s.direction,
            repId: s.selectedRep?.id,
            notes: s.notes,
            name: s.name,
            description: s.description,
            items: s.items,
          )
        : await _templateRepo.updateTemplate(
            id: s.id!,
            entityId: s.selectedEntity!.id,
            direction: s.direction,
            repId: s.selectedRep?.id,
            notes: s.notes,
            name: s.name,
            description: s.description,
            items: s.items,
          );
    if (isClosed) return;

    switch (result) {
      case AppSuccess():
        logger.i('TemplateEditorCubit → saved');
        safeEmit(s.copyWith(isSaving: false, justSaved: true));
      case AppFailure(:final error):
        logger.e('TemplateEditorCubit → save failed: ${error.message}');
        safeEmit(s.copyWith(isSaving: false, actionError: error.message));
    }
  }

  Future<void> deleteExisting() async {
    final s = state;
    if (s is! TemplateEditorReady || s.isNew) return;
    logger.d('TemplateEditorCubit → deleteExisting ${s.id}');
    safeEmit(s.copyWith(isDeleting: true));

    final result = await _templateRepo.deleteTemplate(s.id!);
    if (isClosed) return;

    switch (result) {
      case AppSuccess():
        logger.i('TemplateEditorCubit → deleted ${s.id}');
        safeEmit(s.copyWith(isDeleting: false, justDeleted: true));
      case AppFailure(:final error):
        logger.e('TemplateEditorCubit → delete failed: ${error.message}');
        safeEmit(s.copyWith(isDeleting: false, actionError: error.message));
    }
  }
}
