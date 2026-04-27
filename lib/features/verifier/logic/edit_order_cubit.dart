import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../data/inventory_repository.dart';
import '../data/order_repository.dart';
import 'create_order_cubit.dart' show DraftOrderItem;

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

// Sentinel used by copyWith to distinguish "don't change" from "set to null".
const _stockErrorSentinel = Object();

class EditOrderReady extends EditOrderState {
  final Order originalOrder;
  final List<InventoryItem> inventory;
  final List<EditAction> pendingActions;
  final String? reason;
  final String? stockError;
  final Map<String, String> receipts;

  const EditOrderReady({
    required this.originalOrder,
    required this.inventory,
    this.pendingActions = const [],
    this.reason,
    this.stockError,
    required this.receipts,
  });

  EditOrderReady copyWith({
    List<EditAction>? pendingActions,
    String? reason,
    Object? stockError = _stockErrorSentinel,
    Map<String, String>? receipts,
  }) {
    return EditOrderReady(
      originalOrder: originalOrder,
      inventory: inventory,
      pendingActions: pendingActions ?? this.pendingActions,
      reason: reason ?? this.reason,
      stockError: identical(stockError, _stockErrorSentinel)
          ? this.stockError
          : stockError as String?,
      receipts: receipts ?? this.receipts,
    );
  }

  bool get canSubmit =>
      pendingActions.isNotEmpty &&
      reason != null &&
      reason!.trim().isNotEmpty;

  /// Returns the effective items list after applying all pending actions.
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
          break; // Added items don't have an OrderItem yet
      }
    }
    return items;
  }

  /// Returns draft items that will be added (from AddItemAction).
  List<DraftOrderItem> get addedItems => pendingActions
      .whereType<AddItemAction>()
      .map((a) => a.item)
      .toList();

  @override
  List<Object?> get props => [originalOrder, pendingActions, reason, stockError, receipts];
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

class EditOrderCubit extends Cubit<EditOrderState> {
  final OrderRepository _orderRepo;
  final InventoryRepository _inventoryRepo;
  final String orderId;

  EditOrderCubit(this._orderRepo, this._inventoryRepo, this.orderId)
      : super(EditOrderInitial());

  Future<void> loadOrder() async {
    logger.d('EditOrderCubit → loadOrder: $orderId');
    emit(EditOrderLoading());
    try {
      final results = await Future.wait([
        _orderRepo.fetchOrderForEdit(orderId),
        _inventoryRepo.fetchInventory(),
        _orderRepo.fetchReceipts(orderId),
      ]);
      emit(EditOrderReady(
        originalOrder: results[0] as Order,
        inventory: results[1] as List<InventoryItem>,
        receipts: results[2] as Map<String, String>,
      ));
      logger.i('EditOrderCubit → order loaded for editing');
    } catch (e, st) {
      logger.e('EditOrderCubit → loadOrder failed', error: e, stackTrace: st);
      emit(EditOrderError(e.toString()));
    }
  }

  void updateItemQuantity(String itemId, int newQuantity) {
    final s = state;
    if (s is! EditOrderReady) return;

    final item = s.originalOrder.items.firstWhere((i) => i.id == itemId);

    // Increasing qty after release means taking more from stock — validate.
    if (newQuantity > item.quantity && item.inventoryId != null) {
      final needed = newQuantity - item.quantity;
      final invItem = s.inventory.where((i) => i.id == item.inventoryId).firstOrNull;
      if (invItem == null || invItem.quantity < needed) {
        emit(s.copyWith(
          stockError:
              'المخزون غير كافٍ — المتوفر: ${invItem?.quantity ?? 0}، المطلوب: $needed',
        ));
        return;
      }
    }

    // Remove any existing update action for this item
    final updated = List<EditAction>.from(s.pendingActions)
      ..removeWhere((a) => a is UpdateQuantityAction && a.itemId == itemId);

    // Only add if quantity actually changed from original
    if (newQuantity != item.quantity) {
      updated.add(UpdateQuantityAction(
        itemId: itemId,
        itemName: item.displayName,
        oldQuantity: item.quantity,
        newQuantity: newQuantity,
      ));
    }

    emit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void removeItem(String itemId) {
    final s = state;
    if (s is! EditOrderReady) return;

    final item = s.originalOrder.items.firstWhere((i) => i.id == itemId);

    // Remove any existing update action for this item (can't update what's removed)
    final updated = List<EditAction>.from(s.pendingActions)
      ..removeWhere((a) => a is UpdateQuantityAction && a.itemId == itemId);

    // Add removal if not already present
    if (!updated.any((a) => a is RemoveItemAction && a.itemId == itemId)) {
      updated.add(RemoveItemAction(
        itemId: itemId,
        itemName: item.displayName,
        quantity: item.quantity,
      ));
    }

    emit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void addInventoryItem(InventoryItem item, int quantity) {
    final s = state;
    if (s is! EditOrderReady) return;

    // Adding a new item deducts from stock — validate.
    if (item.quantity < quantity) {
      emit(s.copyWith(
        stockError:
            'المخزون غير كافٍ — المتوفر: ${item.quantity}، المطلوب: $quantity',
      ));
      return;
    }

    final updated = List<EditAction>.from(s.pendingActions)
      ..add(AddItemAction(
        item: DraftOrderItem(
          inventoryId: item.id,
          inventoryName: item.itemName,
          quantity: quantity,
          isCustom: false,
        ),
      ));
    emit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void addCustomItem(String description, int quantity, {String? sourceInventoryId}) {
    final s = state;
    if (s is! EditOrderReady) return;
    final updated = List<EditAction>.from(s.pendingActions)
      ..add(AddItemAction(
        item: DraftOrderItem(
          quantity: quantity,
          isCustom: true,
          customDescription: description,
          sourceInventoryId: sourceInventoryId,
        ),
      ));
    emit(s.copyWith(pendingActions: updated, stockError: null));
  }

  void undoAction(int index) {
    final s = state;
    if (s is! EditOrderReady) return;
    final updated = List<EditAction>.from(s.pendingActions)..removeAt(index);
    emit(s.copyWith(pendingActions: updated));
  }

  void setReason(String reason) {
    final s = state;
    if (s is! EditOrderReady) return;
    emit(s.copyWith(reason: reason));
  }

  Future<void> submit() async {
    final s = state;
    if (s is! EditOrderReady || !s.canSubmit) return;
    logger.d('EditOrderCubit → submit');
    emit(EditOrderSubmitting());
    try {
      // Build RPC parameters from pending actions
      final updates = <Map<String, dynamic>>[];
      final removals = <String>[];
      final additions = <Map<String, dynamic>>[];

      for (final action in s.pendingActions) {
        switch (action) {
          case UpdateQuantityAction(:final itemId, :final newQuantity):
            updates.add({
              'item_id': itemId,
              'new_quantity': newQuantity,
            });
          case RemoveItemAction(:final itemId):
            removals.add(itemId);
          case AddItemAction(:final item):
            additions.add(item.toInsertMap());
        }
      }

      await _orderRepo.editOrderItems(
        orderId: orderId,
        reason: s.reason!,
        updates: updates,
        removals: removals,
        additions: additions,
      );

      // Reconcile inventory: compute deltas from the pending actions and apply
      // them in a single bulk RPC call.
      final deltas = _computeInventoryDeltas(s);
      if (deltas.isNotEmpty) {
        await _inventoryRepo.incrementStockBulk(deltas);
      }

      emit(EditOrderSuccess());
    } catch (e, st) {
      logger.e('EditOrderCubit → submit failed', error: e, stackTrace: st);
      emit(EditOrderError(e.toString()));
    }
  }

  /// Computes inventory deltas from all pending actions.
  ///
  /// Positive delta  → stock increases (qty decrease / item removal).
  /// Negative delta  → stock decreases (qty increase / new item addition).
  /// Custom items (no inventoryId) are skipped — they don't touch inventory.
  Map<String, int> _computeInventoryDeltas(EditOrderReady s) {
    final Map<String, int> deltas = {};

    for (final action in s.pendingActions) {
      switch (action) {
        case UpdateQuantityAction(:final itemId, :final oldQuantity, :final newQuantity):
          final orderItem = s.originalOrder.items.firstWhere((i) => i.id == itemId);
          final invId = orderItem.inventoryId;
          if (invId != null) {
            final delta = oldQuantity - newQuantity;
            deltas[invId] = (deltas[invId] ?? 0) + delta;
          }
        case RemoveItemAction(:final itemId, :final quantity):
          final orderItem = s.originalOrder.items.firstWhere((i) => i.id == itemId);
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
