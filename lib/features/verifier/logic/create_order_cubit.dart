import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../data/entity_repository.dart';
import '../data/inventory_repository.dart';
import '../data/order_repository.dart';

// A draft item being added to the order
class DraftOrderItem extends Equatable {
  final String? inventoryId;
  final String? inventoryName;
  final int quantity;
  final bool isCustom;
  final String? customDescription;

  const DraftOrderItem({
    this.inventoryId,
    this.inventoryName,
    required this.quantity,
    required this.isCustom,
    this.customDescription,
  });

  String get displayName =>
      isCustom ? (customDescription ?? 'صنف مخصص') : (inventoryName ?? '');

  Map<String, dynamic> toInsertMap() => {
        if (inventoryId != null) 'inventory_id': inventoryId,
        'quantity': quantity,
        'is_custom': isCustom,
        if (customDescription != null) 'custom_description': customDescription,
      };

  @override
  List<Object?> get props =>
      [inventoryId, quantity, isCustom, customDescription];
}

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
  final List<InventoryItem> inventory;
  final OrderDirection direction;
  final Entity? selectedEntity;
  final Profile? selectedRep;
  final List<DraftOrderItem> items;
  final String? notes;

  const CreateOrderReady({
    required this.entities,
    required this.reps,
    required this.inventory,
    required this.direction,
    this.selectedEntity,
    this.selectedRep,
    this.items = const [],
    this.notes,
  });

  CreateOrderReady copyWith({
    OrderDirection? direction,
    Entity? selectedEntity,
    bool clearEntity = false,
    Profile? selectedRep,
    bool clearRep = false,
    List<DraftOrderItem>? items,
    String? notes,
  }) {
    return CreateOrderReady(
      entities: entities,
      reps: reps,
      inventory: inventory,
      direction: direction ?? this.direction,
      selectedEntity: clearEntity ? null : (selectedEntity ?? this.selectedEntity),
      selectedRep: clearRep ? null : (selectedRep ?? this.selectedRep),
      items: items ?? this.items,
      notes: notes ?? this.notes,
    );
  }

  bool get canSubmit =>
      selectedEntity != null &&
      items.isNotEmpty &&
      (direction == OrderDirection.inboundExternal || selectedRep != null);

  @override
  List<Object?> get props =>
      [direction, selectedEntity, selectedRep, items, notes];
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

  CreateOrderCubit(
    this._orderRepo,
    this._entityRepo,
    this._inventoryRepo,
  ) : super(CreateOrderInitial());

  Future<void> loadLookups() async {
    logger.d('CreateOrderCubit → loadLookups');
    emit(CreateOrderLoadingLookups());
    try {
      final results = await Future.wait([
        _entityRepo.fetchEntities(),
        _orderRepo.fetchReps(),
        _inventoryRepo.fetchInventory(),
      ]);
      emit(CreateOrderReady(
        entities: results[0] as List<Entity>,
        reps: results[1] as List<Profile>,
        inventory: results[2] as List<InventoryItem>,
        direction: OrderDirection.outbound,
      ));
      logger.i('CreateOrderCubit → lookups loaded');
    } catch (e, st) {
      logger.e('CreateOrderCubit → loadLookups failed', error: e, stackTrace: st);
      emit(CreateOrderError(e.toString()));
    }
  }

  void setDirection(OrderDirection direction) {
    final s = state;
    if (s is! CreateOrderReady) return;
    emit(s.copyWith(direction: direction, clearRep: direction == OrderDirection.inboundExternal));
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
      ..add(DraftOrderItem(
        inventoryId: item.id,
        inventoryName: item.itemName,
        quantity: quantity,
        isCustom: false,
      ));
    emit(s.copyWith(items: updated));
  }

  void addCustomItem(String description, int quantity) {
    final s = state;
    if (s is! CreateOrderReady) return;
    final updated = List<DraftOrderItem>.from(s.items)
      ..add(DraftOrderItem(
        quantity: quantity,
        isCustom: true,
        customDescription: description,
      ));
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

  Future<void> submit() async {
    final s = state;
    if (s is! CreateOrderReady || !s.canSubmit) return;
    logger.d('CreateOrderCubit → submit');
    emit(CreateOrderSubmitting());
    try {
      String directionStr;
      switch (s.direction) {
        case OrderDirection.inboundRep:
          directionStr = 'inbound_rep';
        case OrderDirection.inboundExternal:
          directionStr = 'inbound_external';
        default:
          directionStr = 'outbound';
      }
      final orderId = await _orderRepo.createOrder(
        direction: directionStr,
        entityId: s.selectedEntity!.id,
        repId: s.selectedRep?.id,
        notes: s.notes,
        items: s.items.map((i) => i.toInsertMap()).toList(),
      );
      emit(CreateOrderSuccess(orderId));
    } catch (e, st) {
      logger.e('CreateOrderCubit → submit failed', error: e, stackTrace: st);
      emit(CreateOrderError(e.toString()));
    }
  }
}
