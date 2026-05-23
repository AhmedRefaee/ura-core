import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/draft_order_item.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_template.dart';
import '../../../shared/models/profile.dart';
import '../data/entity_repository.dart';
import '../data/inventory_repository.dart';
import '../data/order_repository.dart';
import '../data/order_template_repository.dart';

export '../../../shared/models/draft_order_item.dart' show DraftOrderItem;

abstract class CreateOrderState extends Equatable {
  const CreateOrderState();
  @override
  List<Object?> get props => [];
}

class CreateOrderInitial extends CreateOrderState {}

class CreateOrderLoadingLookups extends CreateOrderState {}

class CreateOrderReady extends CreateOrderState {
  final List<Entity> entities;
  final List<Profile> reps;
  final Map<String, OrderStatus> repLatestStatuses;
  final List<InventoryItem> inventory;
  final OrderDirection direction;
  final Entity? selectedEntity;
  final Profile? selectedRep;
  final List<DraftOrderItem> items;
  final String? notes;
  final bool templateSaveSucceeded;

  const CreateOrderReady({
    required this.entities,
    required this.reps,
    this.repLatestStatuses = const {},
    required this.inventory,
    required this.direction,
    this.selectedEntity,
    this.selectedRep,
    this.items = const [],
    this.notes,
    this.templateSaveSucceeded = false,
  });

  CreateOrderReady copyWith({
    OrderDirection? direction,
    Entity? selectedEntity,
    bool clearEntity = false,
    Profile? selectedRep,
    bool clearRep = false,
    List<DraftOrderItem>? items,
    String? notes,
    bool clearNotes = false,
    bool templateSaveSucceeded = false,
  }) {
    return CreateOrderReady(
      entities: entities,
      reps: reps,
      repLatestStatuses: repLatestStatuses,
      inventory: inventory,
      direction: direction ?? this.direction,
      selectedEntity: clearEntity
          ? null
          : (selectedEntity ?? this.selectedEntity),
      selectedRep: clearRep ? null : (selectedRep ?? this.selectedRep),
      items: items ?? this.items,
      notes: clearNotes ? null : (notes ?? this.notes),
      templateSaveSucceeded: templateSaveSucceeded,
    );
  }

  bool get canSubmit =>
      selectedEntity != null &&
      items.isNotEmpty &&
      (direction == OrderDirection.inboundExternal || selectedRep != null);

  @override
  List<Object?> get props => [
    direction,
    selectedEntity,
    selectedRep,
    items,
    notes,
    templateSaveSucceeded,
    repLatestStatuses,
  ];
}

class CreateOrderSubmitting extends CreateOrderState {}

class CreateOrderSuccess extends CreateOrderState {
  final String orderId;
  const CreateOrderSuccess(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

class CreateOrderError extends CreateOrderState {
  final String message;
  const CreateOrderError(this.message);
  @override
  List<Object?> get props => [message];
}

class CreateOrderCubit extends Cubit<CreateOrderState> {
  final OrderRepository _orderRepo;
  final EntityRepository _entityRepo;
  final InventoryRepository _inventoryRepo;
  final OrderTemplateRepository _templateRepo;

  CreateOrderCubit(
    this._orderRepo,
    this._entityRepo,
    this._inventoryRepo,
    this._templateRepo,
  ) : super(CreateOrderInitial());

  Future<void> loadLookups() async {
    logger.d('CreateOrderCubit → loadLookups');
    emit(CreateOrderLoadingLookups());

    final results = await Future.wait([
      _entityRepo.fetchEntities(),
      _orderRepo.fetchReps(),
      _orderRepo.fetchLatestOrderStatusByRep(),
      _inventoryRepo.fetchInventory(),
    ]);

    final entitiesResult = results[0] as AppResult<List<Entity>>;
    final repsResult = results[1] as AppResult<List<Profile>>;
    final repStatusesResult = results[2] as AppResult<Map<String, OrderStatus>>;
    final inventoryResult = results[3] as AppResult<List<InventoryItem>>;

    final entitiesError = entitiesResult.failureOrNull;
    if (entitiesError != null) {
      logger.e(
        'CreateOrderCubit → loadLookups failed: ${entitiesError.message}',
      );
      emit(CreateOrderError(entitiesError.message));
      return;
    }
    final repsError = repsResult.failureOrNull;
    if (repsError != null) {
      logger.e('CreateOrderCubit → loadLookups failed: ${repsError.message}');
      emit(CreateOrderError(repsError.message));
      return;
    }
    final repStatusesError = repStatusesResult.failureOrNull;
    if (repStatusesError != null) {
      logger.e(
        'CreateOrderCubit → rep status lookup skipped: ${repStatusesError.message}',
      );
    }
    final inventoryError = inventoryResult.failureOrNull;
    if (inventoryError != null) {
      logger.e(
        'CreateOrderCubit → loadLookups failed: ${inventoryError.message}',
      );
      emit(CreateOrderError(inventoryError.message));
      return;
    }

    emit(
      CreateOrderReady(
        entities: (entitiesResult as AppSuccess<List<Entity>>).data,
        reps: (repsResult as AppSuccess<List<Profile>>).data,
        repLatestStatuses:
            repStatusesResult is AppSuccess<Map<String, OrderStatus>>
            ? repStatusesResult.data
            : const {},
        inventory: (inventoryResult as AppSuccess<List<InventoryItem>>).data,
        direction: OrderDirection.outbound,
      ),
    );
    logger.i('CreateOrderCubit → lookups loaded');
  }

  void setDirection(OrderDirection direction) {
    final s = state;
    if (s is! CreateOrderReady) return;
    emit(
      s.copyWith(
        direction: direction,
        clearRep: direction == OrderDirection.inboundExternal,
      ),
    );
  }

  void selectEntity(Entity entity) {
    final s = state;
    if (s is! CreateOrderReady) return;
    emit(s.copyWith(selectedEntity: entity));
  }

  void selectRep(Profile rep) {
    final s = state;
    if (s is! CreateOrderReady) return;
    emit(s.copyWith(selectedRep: rep));
  }

  void addInventoryItem(InventoryItem item, int quantity) {
    final s = state;
    if (s is! CreateOrderReady) return;
    final updated = List<DraftOrderItem>.from(s.items)
      ..add(
        DraftOrderItem(
          inventoryId: item.id,
          inventoryName: item.itemName,
          quantity: quantity,
          isCustom: false,
        ),
      );
    emit(s.copyWith(items: updated));
  }

  void addCustomItem(
    String description,
    int quantity, {
    String? sourceInventoryId,
  }) {
    final s = state;
    if (s is! CreateOrderReady) return;
    final updated = List<DraftOrderItem>.from(s.items)
      ..add(
        DraftOrderItem(
          quantity: quantity,
          isCustom: true,
          customDescription: description,
          sourceInventoryId: sourceInventoryId,
        ),
      );
    emit(s.copyWith(items: updated));
  }

  void addMultipleItems(
    List<({InventoryItem item, int quantity})> itemsWithQuantities,
  ) {
    final s = state;
    if (s is! CreateOrderReady) return;
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
    emit(s.copyWith(items: updated));
  }

  void removeItem(int index) {
    final s = state;
    if (s is! CreateOrderReady) return;
    final updated = List<DraftOrderItem>.from(s.items)..removeAt(index);
    emit(s.copyWith(items: updated));
  }

  void setNotes(String notes) {
    final s = state;
    if (s is! CreateOrderReady) return;
    emit(s.copyWith(notes: notes));
  }

  void applyCopyFromOrder(Order order) {
    final s = state;
    if (s is! CreateOrderReady) return;
    final draftItems = order.items
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
        .toList();
    final entityMatches = s.entities.where((e) => e.id == order.entityId);
    final entity = entityMatches.isEmpty ? null : entityMatches.first;
    final repMatches = order.repId == null
        ? const <Profile>[]
        : s.reps.where((r) => r.id == order.repId);
    final rep = repMatches.isEmpty ? null : repMatches.first;
    emit(
      s.copyWith(
        direction: order.direction,
        selectedEntity: entity,
        clearEntity: entity == null,
        selectedRep: rep,
        clearRep: rep == null,
        items: draftItems,
        notes: order.notes,
        clearNotes: order.notes == null,
      ),
    );
    logger.i('CreateOrderCubit → applied copy from order ${order.id}');
  }

  void applyTemplate(OrderTemplate template) {
    final s = state;
    if (s is! CreateOrderReady) return;
    final draftItems = template.items
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
        .toList();
    final repsWithId = s.reps.where((r) => r.id == template.repId);
    final rep = repsWithId.isEmpty ? null : repsWithId.first;
    emit(
      s.copyWith(
        direction: template.direction,
        selectedRep: rep,
        clearRep: rep == null,
        items: draftItems,
        notes: template.notes,
        clearNotes: template.notes == null,
      ),
    );
  }

  Future<void> saveAsTemplate() async {
    final s = state;
    if (s is! CreateOrderReady || s.selectedEntity == null || s.items.isEmpty) {
      return;
    }
    final result = await _templateRepo.saveManual(
      entityId: s.selectedEntity!.id,
      direction: s.direction,
      repId: s.selectedRep?.id,
      notes: s.notes,
      items: s.items,
    );
    if (isClosed) return;
    switch (result) {
      case AppSuccess():
        emit(s.copyWith(templateSaveSucceeded: true));
        logger.i('CreateOrderCubit → template saved');
      case AppFailure(:final error):
        logger.e('CreateOrderCubit → saveAsTemplate failed: ${error.message}');
    }
  }

  Future<void> submit() async {
    final s = state;
    if (s is! CreateOrderReady || !s.canSubmit) return;
    logger.d('CreateOrderCubit → submit');
    emit(CreateOrderSubmitting());

    String directionStr;
    switch (s.direction) {
      case OrderDirection.inboundRep:
        directionStr = 'inbound_rep';
      case OrderDirection.inboundExternal:
        directionStr = 'inbound_external';
      default:
        directionStr = 'outbound';
    }

    final result = await _orderRepo.createOrder(
      direction: directionStr,
      entityId: s.selectedEntity!.id,
      repId: s.selectedRep?.id,
      notes: s.notes,
      items: s.items.map((i) => i.toInsertMap()).toList(),
    );

    switch (result) {
      case AppSuccess(:final data):
        emit(CreateOrderSuccess(data));
        // Track usage (non-critical — failure is only logged)
        _templateRepo
            .trackUsage(
              entityId: s.selectedEntity!.id,
              direction: s.direction,
              repId: s.selectedRep?.id,
              notes: s.notes,
              items: s.items,
            )
            .then((r) {
              if (r is AppFailure) {
                logger.e(
                  'CreateOrderCubit → trackUsage failed (non-critical): ${r.error.message}',
                );
              }
            });
      case AppFailure(:final error):
        logger.e('CreateOrderCubit → submit failed: ${error.message}');
        emit(CreateOrderError(error.message));
    }
  }
}
