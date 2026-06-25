import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../data/inventory_repository.dart';
import '../data/order_repository.dart';
import '../../../shared/models/draft_order_item.dart';

import '../../../core/logic/safe_emit.dart';
// ── Edit Actions ──────────────────────────────────────────────────────

sealed class EditAction extends Equatable {
  const EditAction();
}

class UpdateQuantityAction extends EditAction {
  final String itemId;
  final String itemName;
  final int oldQuantity;
  final int newQuantity;

  const UpdateQuantityAction({
    required this.itemId,
    required this.itemName,
    required this.oldQuantity,
    required this.newQuantity,
  });

  @override
  List<Object?> get props => [itemId, oldQuantity, newQuantity];
}

class RemoveItemAction extends EditAction {
  final String itemId;
  final String itemName;
  final int quantity;

  const RemoveItemAction({
    required this.itemId,
    required this.itemName,
    required this.quantity,
  });

  @override
  List<Object?> get props => [itemId];
}

class AddItemAction extends EditAction {
  final DraftOrderItem item;

  const AddItemAction({required this.item});

  @override
  List<Object?> get props => [item];
}

// ── States ────────────────────────────────────────────────────────────

abstract class EditOrderState extends Equatable {
  const EditOrderState();
  @override
  List<Object?> get props => [];
}

class EditOrderInitial extends EditOrderState {}

class EditOrderLoading extends EditOrderState {}

const _stockErrorSentinel = Object();

class EditOrderReady extends EditOrderState {
  final Order originalOrder;
  final List<InventoryItem> inventory;
  final List<EditAction> pendingActions;
  final String? reason;
  final String? stockError;

  const EditOrderReady({
    required this.originalOrder,
    required this.inventory,
    this.pendingActions = const [],
    this.reason,
    this.stockError,
  });

  EditOrderReady copyWith({
    List<EditAction>? pendingActions,
    String? reason,
    Object? stockError = _stockErrorSentinel,
  }) {
    return EditOrderReady(
      originalOrder: originalOrder,
      inventory: inventory,
      pendingActions: pendingActions ?? this.pendingActions,
      reason: reason ?? this.reason,
      stockError: identical(stockError, _stockErrorSentinel)
          ? this.stockError
          : stockError as String?,
    );
  }

  bool get canSubmit =>
      pendingActions.isNotEmpty && reason != null && reason!.trim().isNotEmpty;

  List<OrderItem> get effectiveItems {
    final items = List<OrderItem>.from(originalOrder.items);
    for (final action in pendingActions) {
      switch (action) {
        case UpdateQuantityAction(:final itemId, :final newQuantity):
          final idx = items.indexWhere((i) => i.id == itemId);
          if (idx != -1) {
            final old = items[idx];
            items[idx] = OrderItem(
              id: old.id,
              orderId: old.orderId,
              inventoryId: old.inventoryId,
              inventoryName: old.inventoryName,
              quantity: newQuantity,
              finalQuantity: old.finalQuantity,
              isCustom: old.isCustom,
              customDescription: old.customDescription,
              sourceInventoryId: old.sourceInventoryId,
              checkStatus: old.checkStatus,
            );
          }
        case RemoveItemAction(:final itemId):
          items.removeWhere((i) => i.id == itemId);
        case AddItemAction():
          break;
      }
    }
    return items;
  }

  List<DraftOrderItem> get addedItems =>
      pendingActions.whereType<AddItemAction>().map((a) => a.item).toList();

  @override
  List<Object?> get props => [
    originalOrder,
    pendingActions,
    reason,
    stockError,
  ];
}

class EditOrderSubmitting extends EditOrderState {}

class EditOrderSuccess extends EditOrderState {}

class EditOrderError extends EditOrderState {
  final String message;
  const EditOrderError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────

class EditOrderCubit extends Cubit<EditOrderState>
    with SafeEmit<EditOrderState> {
  final OrderRepository _orderRepo;
  final InventoryRepository _inventoryRepo;
  final String orderId;

  EditOrderCubit(this._orderRepo, this._inventoryRepo, this.orderId)
    : super(EditOrderInitial());

  Future<void> loadOrder() async {
    logger.d('EditOrderCubit → loadOrder: $orderId');
    safeEmit(EditOrderLoading());

    final results = await Future.wait([
      _orderRepo.fetchOrderForEdit(orderId),
      _inventoryRepo.fetchInventory(),
    ]);

    final orderResult = results[0] as AppResult<Order>;
    final inventoryResult = results[1] as AppResult<List<InventoryItem>>;

    final orderError = orderResult.failureOrNull;
    if (orderError != null) {
      logger.e('EditOrderCubit → loadOrder failed: ${orderError.message}');
      safeEmit(EditOrderError(orderError.message));
      return;
    }
    final inventoryError = inventoryResult.failureOrNull;
    if (inventoryError != null) {
      logger.e('EditOrderCubit → loadOrder failed: ${inventoryError.message}');
      safeEmit(EditOrderError(inventoryError.message));
      return;
    }

    safeEmit(
      EditOrderReady(
        originalOrder: (orderResult as AppSuccess<Order>).data,
        inventory: (inventoryResult as AppSuccess<List<InventoryItem>>).data,
      ),
    );
    logger.i('EditOrderCubit → order loaded for editing');
  }

  void updateItemQuantity(String itemId, int newQuantity) {
    final s = state;
    if (s is! EditOrderReady) return;
    final item = s.originalOrder.items.firstWhere((i) => i.id == itemId);
    final updated = List<EditAction>.from(s.pendingActions)
      ..removeWhere((a) => a is UpdateQuantityAction && a.itemId == itemId);
    if (newQuantity != item.quantity) {
      updated.add(
        UpdateQuantityAction(
          itemId: itemId,
          itemName: item.displayName,
          oldQuantity: item.quantity,
          newQuantity: newQuantity,
        ),
      );
    }
    safeEmit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void removeItem(String itemId) {
    final s = state;
    if (s is! EditOrderReady) return;
    final item = s.originalOrder.items.firstWhere((i) => i.id == itemId);
    final updated = List<EditAction>.from(s.pendingActions)
      ..removeWhere((a) => a is UpdateQuantityAction && a.itemId == itemId);
    if (!updated.any((a) => a is RemoveItemAction && a.itemId == itemId)) {
      updated.add(
        RemoveItemAction(
          itemId: itemId,
          itemName: item.displayName,
          quantity: item.quantity,
        ),
      );
    }
    safeEmit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void addInventoryItem(InventoryItem item, int quantity) {
    final s = state;
    if (s is! EditOrderReady) return;
    final updated = List<EditAction>.from(s.pendingActions)
      ..add(
        AddItemAction(
          item: DraftOrderItem(
            inventoryId: item.id,
            inventoryName: item.itemName,
            quantity: quantity,
            isCustom: false,
          ),
        ),
      );
    safeEmit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void addCustomItem(
    String description,
    int quantity, {
    String? sourceInventoryId,
  }) {
    final s = state;
    if (s is! EditOrderReady) return;
    final updated = List<EditAction>.from(s.pendingActions)
      ..add(
        AddItemAction(
          item: DraftOrderItem(
            quantity: quantity,
            isCustom: true,
            customDescription: description,
            sourceInventoryId: sourceInventoryId,
          ),
        ),
      );
    safeEmit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void undoAction(int index) {
    final s = state;
    if (s is! EditOrderReady) return;
    final updated = List<EditAction>.from(s.pendingActions)..removeAt(index);
    safeEmit(s.copyWith(pendingActions: updated));
  }

  void setReason(String reason) {
    final s = state;
    if (s is! EditOrderReady) return;
    safeEmit(s.copyWith(reason: reason));
  }

  Future<void> submit() async {
    final s = state;
    if (s is! EditOrderReady || !s.canSubmit) return;
    logger.d('EditOrderCubit → submit');
    safeEmit(EditOrderSubmitting());

    final updates = <Map<String, dynamic>>[];
    final removals = <String>[];
    final additions = <Map<String, dynamic>>[];

    for (final action in s.pendingActions) {
      switch (action) {
        case UpdateQuantityAction(:final itemId, :final newQuantity):
          updates.add({'item_id': itemId, 'new_quantity': newQuantity});
        case RemoveItemAction(:final itemId):
          removals.add(itemId);
        case AddItemAction(:final item):
          additions.add(item.toInsertMap());
      }
    }

    final editResult = await _orderRepo.editOrderItems(
      orderId: orderId,
      reason: s.reason!,
      updates: updates,
      removals: removals,
      additions: additions,
    );

    switch (editResult) {
      case AppFailure(:final error):
        logger.e('EditOrderCubit → submit failed: ${error.message}');
        safeEmit(EditOrderError(error.message));
        return;
      case AppSuccess():
        break;
    }

    final deltas = _computeInventoryDeltas(s);
    if (deltas.isNotEmpty) {
      final stockResult = await _inventoryRepo.incrementStockBulk(deltas);
      final stockError = stockResult.failureOrNull;
      if (stockError != null) {
        logger.e(
          'EditOrderCubit → incrementStockBulk failed: ${stockError.message}',
        );
        safeEmit(EditOrderError(stockError.message));
        return;
      }
    }

    safeEmit(EditOrderSuccess());
  }

  Map<String, int> _computeInventoryDeltas(EditOrderReady s) {
    final Map<String, int> deltas = {};
    for (final action in s.pendingActions) {
      switch (action) {
        case UpdateQuantityAction(
          :final itemId,
          :final oldQuantity,
          :final newQuantity,
        ):
          final orderItem = s.originalOrder.items.firstWhere(
            (i) => i.id == itemId,
          );
          final invId = orderItem.inventoryId;
          if (invId != null) {
            deltas[invId] = (deltas[invId] ?? 0) + (oldQuantity - newQuantity);
          }
        case RemoveItemAction(:final itemId, :final quantity):
          final orderItem = s.originalOrder.items.firstWhere(
            (i) => i.id == itemId,
          );
          final invId = orderItem.inventoryId;
          if (invId != null) {
            deltas[invId] = (deltas[invId] ?? 0) + quantity;
          }
        case AddItemAction(:final item):
          final invId = item.inventoryId;
          if (invId != null) {
            deltas[invId] = (deltas[invId] ?? 0) - item.quantity;
          }
      }
    }
    return deltas;
  }
}
