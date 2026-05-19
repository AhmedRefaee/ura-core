import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
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
  final Map<String, String> receipts;
  final List<AuditLogEntry> auditLog;
  final Map<String, ItemCheckStatus> pendingStatuses;
  final Map<String, int> editedQuantities;
  final bool isActing;

  const StorageOrderDetailLoaded({
    required this.order,
    this.receipts = const {},
    this.auditLog = const [],
    this.pendingStatuses = const {},
    this.editedQuantities = const {},
    this.isActing = false,
  });

  ItemCheckStatus effectiveStatus(OrderItem item) =>
      pendingStatuses[item.id] ?? item.checkStatus;

  int effectiveQuantity(OrderItem item) =>
      editedQuantities[item.id] ?? item.effectiveQuantity;

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
    List<AuditLogEntry>? auditLog,
    Map<String, ItemCheckStatus>? pendingStatuses,
    Map<String, int>? editedQuantities,
    bool? isActing,
  }) {
    return StorageOrderDetailLoaded(
      order: order ?? this.order,
      receipts: receipts ?? this.receipts,
      auditLog: auditLog ?? this.auditLog,
      pendingStatuses: pendingStatuses ?? this.pendingStatuses,
      editedQuantities: editedQuantities ?? this.editedQuantities,
      isActing: isActing ?? this.isActing,
    );
  }

  @override
  List<Object?> get props =>
      [order, receipts, auditLog, pendingStatuses, editedQuantities, isActing];
}

class StorageOrderDetailError extends StorageOrderDetailState {
  final String message;
  const StorageOrderDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

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

    final results = await Future.wait([
      _repo.fetchOrderDetail(orderId),
      _repo.fetchReceipts(orderId),
      _repo.fetchAuditLog(orderId),
    ]);

    final orderError = results[0].failureOrNull;
    if (orderError != null) {
      logger.e('StorageOrderDetailCubit → load failed: ${orderError.message}');
      emit(StorageOrderDetailError(orderError.message));
      return;
    }
    final receiptsError = results[1].failureOrNull;
    if (receiptsError != null) {
      logger.e('StorageOrderDetailCubit → load failed: ${receiptsError.message}');
      emit(StorageOrderDetailError(receiptsError.message));
      return;
    }
    // Audit log failure is non-fatal — show empty timeline rather than error screen
    final auditLog = results[2] is AppSuccess<List<AuditLogEntry>>
        ? (results[2] as AppSuccess<List<AuditLogEntry>>).data
        : <AuditLogEntry>[];

    final order = (results[0] as AppSuccess<Order>).data;
    emit(StorageOrderDetailLoaded(
      order: order,
      receipts: (results[1] as AppSuccess<Map<String, String>>).data,
      auditLog: auditLog,
    ));
  }

  Future<void> checkItem(String itemId, ItemCheckStatus newStatus) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    final optimistic = Map<String, ItemCheckStatus>.from(s.pendingStatuses)
      ..[itemId] = newStatus;
    emit(s.copyWith(pendingStatuses: optimistic));
    logger.d('StorageOrderDetailCubit → checkItem $itemId → $newStatus (optimistic)');

    final result = newStatus == ItemCheckStatus.pending
        ? await _repo.revertItemCheckStatus(itemId)
        : await _repo.updateItemCheckStatus(itemId, newStatus);

    switch (result) {
      case AppSuccess():
        logger.i('StorageOrderDetailCubit → checkItem saved: $itemId → $newStatus');
      case AppFailure(:final error):
        logger.e('StorageOrderDetailCubit → checkItem failed, rolling back: ${error.message}');
        final current = state;
        if (current is StorageOrderDetailLoaded) {
          final rolledBack = Map<String, ItemCheckStatus>.from(current.pendingStatuses)
            ..remove(itemId);
          emit(current.copyWith(pendingStatuses: rolledBack));
        }
        emit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> editQuantity(String itemId, int quantity) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    final updated = Map<String, int>.from(s.editedQuantities)..[itemId] = quantity;
    emit(s.copyWith(editedQuantities: updated));

    final result = await _repo.updateFinalQuantity(itemId, quantity);
    switch (result) {
      case AppSuccess():
        logger.i('StorageOrderDetailCubit → quantity updated: $itemId → $quantity');
      case AppFailure(:final error):
        logger.e('StorageOrderDetailCubit → editQuantity failed: ${error.message}');
        final current = state;
        if (current is StorageOrderDetailLoaded) {
          final rolledBack = Map<String, int>.from(current.editedQuantities)
            ..remove(itemId);
          emit(current.copyWith(editedQuantities: rolledBack));
        }
        emit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> uploadReceipt({
    required String orderItemId,
    required File imageFile,
  }) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;
    emit(s.copyWith(isActing: true));

    final uploadResult = await _repo.uploadReceipt(
      orderId: orderId,
      orderItemId: orderItemId,
      imageFile: imageFile,
    );
    switch (uploadResult) {
      case AppSuccess(:final data):
        final updatedReceipts = Map<String, String>.from(s.receipts)..[orderItemId] = data;
        final orderResult = await _repo.fetchOrderDetail(orderId);
        switch (orderResult) {
          case AppSuccess(:final data):
            emit(StorageOrderDetailLoaded(
              order: data,
              receipts: updatedReceipts,
              auditLog: s.auditLog,
              pendingStatuses: s.pendingStatuses,
              editedQuantities: s.editedQuantities,
            ));
          case AppFailure(:final error):
            logger.e('StorageOrderDetailCubit → reload after upload failed: ${error.message}');
            emit(StorageOrderDetailError(error.message));
        }
      case AppFailure(:final error):
        logger.e('StorageOrderDetailCubit → uploadReceipt failed: ${error.message}');
        emit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> confirmPickup({String? notes}) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || s.isActing) return;
    logger.d('StorageOrderDetailCubit → confirmPickup: $orderId');
    emit(s.copyWith(isActing: true));
    final result = await _repo.confirmPickup(
      orderId,
      notes: notes,
      finalQuantities: _buildFinalQuantities(s),
    );
    switch (result) {
      case AppSuccess():
        logger.i('StorageOrderDetailCubit → confirmPickup success');
        emit(const StorageOrderDetailSuccess('تم تأكيد الإرسال بنجاح'));
      case AppFailure(:final error):
        logger.e('StorageOrderDetailCubit → confirmPickup failed: ${error.message}');
        emit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> confirmDelivery({String? notes}) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || s.isActing) return;
    logger.d('StorageOrderDetailCubit → confirmDelivery: $orderId');
    emit(s.copyWith(isActing: true));
    final result = await _repo.confirmDelivery(
      orderId,
      notes: notes,
      finalQuantities: _buildFinalQuantities(s),
    );
    switch (result) {
      case AppSuccess():
        logger.i('StorageOrderDetailCubit → confirmDelivery success');
        emit(const StorageOrderDetailSuccess('تم تأكيد الاستلام بنجاح'));
      case AppFailure(:final error):
        logger.e('StorageOrderDetailCubit → confirmDelivery failed: ${error.message}');
        emit(StorageOrderDetailError(error.message));
    }
  }

  List<Map<String, dynamic>> _buildFinalQuantities(StorageOrderDetailLoaded s) {
    return s.order.items
        .where((item) => item.inventoryId != null && !item.isCustom)
        .where((item) => s.editedQuantities.containsKey(item.id))
        .map((item) => {'item_id': item.id, 'quantity': s.editedQuantities[item.id]!})
        .toList();
  }
}
