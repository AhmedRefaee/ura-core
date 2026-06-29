import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../data/storage_repository.dart';

import '../../../core/logic/safe_emit.dart';
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
  final List<AuditLogEntry> auditLog;
  final Map<String, ItemCheckStatus> pendingStatuses;
  final Map<String, double> editedQuantities;
  final bool isActing;

  const StorageOrderDetailLoaded({
    required this.order,
    this.auditLog = const [],
    this.pendingStatuses = const {},
    this.editedQuantities = const {},
    this.isActing = false,
  });

  ItemCheckStatus effectiveStatus(OrderItem item) =>
      pendingStatuses[item.id] ?? item.checkStatus;

  double effectiveQuantity(OrderItem item) =>
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
    List<AuditLogEntry>? auditLog,
    Map<String, ItemCheckStatus>? pendingStatuses,
    Map<String, double>? editedQuantities,
    bool? isActing,
  }) {
    return StorageOrderDetailLoaded(
      order: order ?? this.order,
      auditLog: auditLog ?? this.auditLog,
      pendingStatuses: pendingStatuses ?? this.pendingStatuses,
      editedQuantities: editedQuantities ?? this.editedQuantities,
      isActing: isActing ?? this.isActing,
    );
  }

  @override
  List<Object?> get props => [
    order,
    auditLog,
    pendingStatuses,
    editedQuantities,
    isActing,
  ];
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

class StorageOrderDetailCubit extends Cubit<StorageOrderDetailState>
    with SafeEmit<StorageOrderDetailState> {
  final StorageRepository _repo;
  final String orderId;

  StorageOrderDetailCubit(this._repo, this.orderId)
    : super(StorageOrderDetailInitial());

  Future<void> load() async {
    logger.d('StorageOrderDetailCubit → load: $orderId');
    safeEmit(StorageOrderDetailLoading());

    final results = await Future.wait([
      _repo.fetchOrderDetail(orderId),
      _repo.fetchAuditLog(orderId),
    ]);

    final orderError = results[0].failureOrNull;
    if (orderError != null) {
      logger.e('StorageOrderDetailCubit → load failed: ${orderError.message}');
      safeEmit(StorageOrderDetailError(orderError.message));
      return;
    }
    // Audit log failure is non-fatal — show empty timeline rather than error screen
    final auditLog = results[1] is AppSuccess<List<AuditLogEntry>>
        ? (results[1] as AppSuccess<List<AuditLogEntry>>).data
        : <AuditLogEntry>[];

    final order = (results[0] as AppSuccess<Order>).data;
    safeEmit(StorageOrderDetailLoaded(order: order, auditLog: auditLog));
  }

  Future<void> checkItem(String itemId, ItemCheckStatus newStatus) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    final optimistic = Map<String, ItemCheckStatus>.from(s.pendingStatuses)
      ..[itemId] = newStatus;
    safeEmit(s.copyWith(pendingStatuses: optimistic));
    logger.d(
      'StorageOrderDetailCubit → checkItem $itemId → $newStatus (optimistic)',
    );

    final result = newStatus == ItemCheckStatus.pending
        ? await _repo.revertItemCheckStatus(itemId)
        : await _repo.updateItemCheckStatus(itemId, newStatus);

    switch (result) {
      case AppSuccess():
        logger.i(
          'StorageOrderDetailCubit → checkItem saved: $itemId → $newStatus',
        );
      case AppFailure(:final error):
        logger.e(
          'StorageOrderDetailCubit → checkItem failed, rolling back: ${error.message}',
        );
        final current = state;
        if (current is StorageOrderDetailLoaded) {
          final rolledBack = Map<String, ItemCheckStatus>.from(
            current.pendingStatuses,
          )..remove(itemId);
          safeEmit(current.copyWith(pendingStatuses: rolledBack));
        }
        safeEmit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> editQuantity(String itemId, double quantity) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    final updated = Map<String, double>.from(s.editedQuantities)
      ..[itemId] = quantity;
    safeEmit(s.copyWith(editedQuantities: updated));

    final result = await _repo.updateFinalQuantity(itemId, quantity);
    switch (result) {
      case AppSuccess():
        logger.i(
          'StorageOrderDetailCubit → quantity updated: $itemId → $quantity',
        );
      case AppFailure(:final error):
        logger.e(
          'StorageOrderDetailCubit → editQuantity failed: ${error.message}',
        );
        final current = state;
        if (current is StorageOrderDetailLoaded) {
          final rolledBack = Map<String, double>.from(current.editedQuantities)
            ..remove(itemId);
          safeEmit(current.copyWith(editedQuantities: rolledBack));
        }
        safeEmit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> confirmPickup({String? notes}) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || s.isActing) return;
    logger.d('StorageOrderDetailCubit → confirmPickup: $orderId');
    safeEmit(s.copyWith(isActing: true));
    final result = await _repo.confirmPickup(
      orderId,
      notes: notes,
      finalQuantities: _buildFinalQuantities(s),
    );
    switch (result) {
      case AppSuccess():
        logger.i('StorageOrderDetailCubit → confirmPickup success');
        safeEmit(const StorageOrderDetailSuccess('تم تأكيد الإرسال بنجاح'));
      case AppFailure(:final error):
        logger.e(
          'StorageOrderDetailCubit → confirmPickup failed: ${error.message}',
        );
        safeEmit(StorageOrderDetailError(error.message));
    }
  }

  Future<void> confirmDelivery({String? notes}) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || s.isActing) return;
    logger.d('StorageOrderDetailCubit → confirmDelivery: $orderId');
    safeEmit(s.copyWith(isActing: true));
    final result = await _repo.confirmDelivery(
      orderId,
      notes: notes,
      finalQuantities: _buildFinalQuantities(s),
    );
    switch (result) {
      case AppSuccess():
        logger.i('StorageOrderDetailCubit → confirmDelivery success');
        safeEmit(const StorageOrderDetailSuccess('تم تأكيد الاستلام بنجاح'));
      case AppFailure(:final error):
        logger.e(
          'StorageOrderDetailCubit → confirmDelivery failed: ${error.message}',
        );
        safeEmit(StorageOrderDetailError(error.message));
    }
  }

  List<Map<String, dynamic>> _buildFinalQuantities(StorageOrderDetailLoaded s) {
    return s.order.items
        .where((item) => item.inventoryId != null && !item.isCustom)
        .where((item) => s.editedQuantities.containsKey(item.id))
        .map(
          (item) => {
            'item_id': item.id,
            'quantity': s.editedQuantities[item.id]!,
          },
        )
        .toList();
  }
}
