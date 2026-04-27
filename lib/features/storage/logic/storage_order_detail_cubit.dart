import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../data/storage_repository.dart';

// ─── States ──────────────────────────────────────────────────────────────────

abstract class StorageOrderDetailState extends Equatable {
  const StorageOrderDetailState();
  @override
  List<Object?> get props => [];
}

class StorageOrderDetailInitial extends StorageOrderDetailState {}

class StorageOrderDetailLoading extends StorageOrderDetailState {}

class StorageOrderDetailLoaded extends StorageOrderDetailState {
  final Order order;
  final Map<String, String> receipts; // itemId → imageUrl (Flow 4)

  /// Optimistic check status overrides, rolled back on failure.
  final Map<String, ItemCheckStatus> pendingStatuses;

  /// Optimistic quantity edits by the storage actor before confirming.
  final Map<String, int> editedQuantities;

  /// True while an RPC call is in-flight.
  final bool isActing;

  const StorageOrderDetailLoaded({
    required this.order,
    this.receipts = const {},
    this.pendingStatuses = const {},
    this.editedQuantities = const {},
    this.isActing = false,
  });

  // ── Derived helpers ──────────────────────────────────────────────────────

  ItemCheckStatus effectiveStatus(OrderItem item) =>
      pendingStatuses[item.id] ?? item.checkStatus;

  /// Effective quantity for an item: actor's local edit → DB final_quantity → original quantity.
  int effectiveQuantity(OrderItem item) =>
      editedQuantities[item.id] ?? item.effectiveQuantity;

  /// All items checked or rejected (used as gate for inbound_external delivery).
  bool get allItemsReviewed {
    if (order.items.isEmpty) return false;
    return order.items.every((item) {
      final s = effectiveStatus(item);
      return s == ItemCheckStatus.checked || s == ItemCheckStatus.rejected;
    });
  }

  StorageOrderDetailLoaded copyWith({
    Order? order,
    Map<String, String>? receipts,
    Map<String, ItemCheckStatus>? pendingStatuses,
    Map<String, int>? editedQuantities,
    bool? isActing,
  }) {
    return StorageOrderDetailLoaded(
      order: order ?? this.order,
      receipts: receipts ?? this.receipts,
      pendingStatuses: pendingStatuses ?? this.pendingStatuses,
      editedQuantities: editedQuantities ?? this.editedQuantities,
      isActing: isActing ?? this.isActing,
    );
  }

  @override
  List<Object?> get props =>
      [order, receipts, pendingStatuses, editedQuantities, isActing];
}

class StorageOrderDetailError extends StorageOrderDetailState {
  final String message;
  const StorageOrderDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

/// Emitted after a confirm action (pickup/delivery) completes successfully.
/// The screen should pop back to the home screen on this state.
class StorageOrderDetailSuccess extends StorageOrderDetailState {
  final String message;
  const StorageOrderDetailSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── Cubit ───────────────────────────────────────────────────────────────────

class StorageOrderDetailCubit extends Cubit<StorageOrderDetailState> {
  final StorageRepository _repo;
  final String orderId;

  StorageOrderDetailCubit(this._repo, this.orderId)
      : super(StorageOrderDetailInitial());

  Future<void> load() async {
    logger.d('StorageOrderDetailCubit → load: $orderId');
    emit(StorageOrderDetailLoading());
    try {
      final results = await Future.wait([
        _repo.fetchOrderDetail(orderId),
        _repo.fetchReceipts(orderId),
      ]);
      emit(StorageOrderDetailLoaded(
        order: results[0] as Order,
        receipts: results[1] as Map<String, String>,
      ));
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → load failed', error: e, stackTrace: st);
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  // ── Item check (Flow 4 — inbound_external) ────────────────────────────────

  Future<void> checkItem(String itemId, ItemCheckStatus newStatus) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    // Optimistic update
    final optimistic = Map<String, ItemCheckStatus>.from(s.pendingStatuses)
      ..[itemId] = newStatus;
    emit(s.copyWith(pendingStatuses: optimistic));
    logger.d('StorageOrderDetailCubit → checkItem $itemId → $newStatus (optimistic)');

    try {
      if (newStatus == ItemCheckStatus.pending) {
        await _repo.revertItemCheckStatus(itemId);
      } else {
        await _repo.updateItemCheckStatus(itemId, newStatus);
      }
      logger.i('StorageOrderDetailCubit → checkItem saved: $itemId → $newStatus');
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → checkItem failed, rolling back',
          error: e, stackTrace: st);
      final current = state;
      if (current is StorageOrderDetailLoaded) {
        final rolledBack =
            Map<String, ItemCheckStatus>.from(current.pendingStatuses)
              ..remove(itemId);
        emit(current.copyWith(pendingStatuses: rolledBack));
      }
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  // ── Quantity editing ──────────────────────────────────────────────────────

  /// Updates the local (optimistic) quantity. Persists to DB immediately.
  Future<void> editQuantity(String itemId, int quantity) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    final updated = Map<String, int>.from(s.editedQuantities)..[itemId] = quantity;
    emit(s.copyWith(editedQuantities: updated));

    try {
      await _repo.updateFinalQuantity(itemId, quantity);
      logger.i('StorageOrderDetailCubit → quantity updated: $itemId → $quantity');
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → editQuantity failed', error: e, stackTrace: st);
      // Rollback local edit
      final current = state;
      if (current is StorageOrderDetailLoaded) {
        final rolledBack = Map<String, int>.from(current.editedQuantities)
          ..remove(itemId);
        emit(current.copyWith(editedQuantities: rolledBack));
      }
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  // ── Receipt upload (Flow 4) ───────────────────────────────────────────────

  Future<void> uploadReceipt({
    required String orderItemId,
    required File imageFile,
  }) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;
    emit(s.copyWith(isActing: true));
    try {
      final url = await _repo.uploadReceipt(
        orderId: orderId,
        orderItemId: orderItemId,
        imageFile: imageFile,
      );
      final updatedReceipts = Map<String, String>.from(s.receipts)
        ..[orderItemId] = url;
      final order = await _repo.fetchOrderDetail(orderId);
      emit(StorageOrderDetailLoaded(
        order: order,
        receipts: updatedReceipts,
        pendingStatuses: s.pendingStatuses,
        editedQuantities: s.editedQuantities,
      ));
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → uploadReceipt failed', error: e, stackTrace: st);
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  // ── Confirm actions ───────────────────────────────────────────────────────

  /// Flow 1 (outbound + storage): releases items, decreases inventory.
  Future<void> confirmPickup({String? notes}) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || s.isActing) return;
    logger.d('StorageOrderDetailCubit → confirmPickup: $orderId');
    emit(s.copyWith(isActing: true));
    try {
      final quantities = _buildFinalQuantities(s);
      await _repo.confirmPickup(orderId, notes: notes, finalQuantities: quantities);
      logger.i('StorageOrderDetailCubit → confirmPickup success');
      emit(const StorageOrderDetailSuccess('تم تأكيد الإرسال بنجاح'));
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → confirmPickup failed', error: e, stackTrace: st);
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  /// Flow 3 (inbound_rep) & Flow 4 (inbound_external): receives items, increases inventory.
  Future<void> confirmDelivery({String? notes}) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || s.isActing) return;
    logger.d('StorageOrderDetailCubit → confirmDelivery: $orderId');
    emit(s.copyWith(isActing: true));
    try {
      final quantities = _buildFinalQuantities(s);
      await _repo.confirmDelivery(orderId, notes: notes, finalQuantities: quantities);
      logger.i('StorageOrderDetailCubit → confirmDelivery success');
      emit(const StorageOrderDetailSuccess('تم تأكيد الاستلام بنجاح'));
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → confirmDelivery failed', error: e, stackTrace: st);
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Builds the final_quantities payload from local edits, only for items
  /// that have an inventory_id (non-custom).
  List<Map<String, dynamic>> _buildFinalQuantities(
      StorageOrderDetailLoaded s) {
    return s.order.items
        .where((item) => item.inventoryId != null && !item.isCustom)
        .where((item) => s.editedQuantities.containsKey(item.id))
        .map((item) => {
              'item_id': item.id,
              'quantity': s.editedQuantities[item.id]!,
            })
        .toList();
  }
}
