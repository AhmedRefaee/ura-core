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

  /// Optimistic overrides: itemId → new status, applied immediately on tap.
  /// Rolled back if the DB call fails.
  final Map<String, ItemCheckStatus> pendingStatuses;

  /// True while the approve RPC is in-flight.
  final bool isApproving;

  const StorageOrderDetailLoaded({
    required this.order,
    this.pendingStatuses = const {},
    this.isApproving = false,
  });

  /// Resolves the effective status for an item:
  /// pendingStatuses wins over the DB-confirmed value in order.items.
  ItemCheckStatus effectiveStatus(OrderItem item) =>
      pendingStatuses[item.id] ?? item.checkStatus;

  /// Approve is allowed only when every item is checked or rejected.
  bool get canApprove {
    if (isApproving || order.items.isEmpty) return false;
    return order.items.every((item) {
      final s = effectiveStatus(item);
      return s == ItemCheckStatus.checked || s == ItemCheckStatus.rejected;
    });
  }

  StorageOrderDetailLoaded copyWith({
    Order? order,
    Map<String, ItemCheckStatus>? pendingStatuses,
    bool? isApproving,
  }) {
    return StorageOrderDetailLoaded(
      order: order ?? this.order,
      pendingStatuses: pendingStatuses ?? this.pendingStatuses,
      isApproving: isApproving ?? this.isApproving,
    );
  }

  @override
  List<Object?> get props => [order, pendingStatuses, isApproving];
}

class StorageOrderDetailError extends StorageOrderDetailState {
  final String message;
  const StorageOrderDetailError(this.message);
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
      final order = await _repo.fetchOrderDetail(orderId);
      emit(StorageOrderDetailLoaded(order: order));
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → load failed', error: e, stackTrace: st);
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  Future<void> checkItem(String itemId, ItemCheckStatus newStatus) async {
    final s = state;
    if (s is! StorageOrderDetailLoaded) return;

    // 1. Optimistic update — UI reflects change immediately
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
      // Rollback: remove the optimistic entry
      final current = state;
      if (current is StorageOrderDetailLoaded) {
        final rolledBack = Map<String, ItemCheckStatus>.from(current.pendingStatuses)
          ..remove(itemId);
        emit(current.copyWith(pendingStatuses: rolledBack));
      }
      emit(StorageOrderDetailError(e.toString()));
    }
  }

  Future<void> approveOrder() async {
    final s = state;
    if (s is! StorageOrderDetailLoaded || !s.canApprove) return;
    logger.d('StorageOrderDetailCubit → approveOrder: $orderId');
    emit(s.copyWith(isApproving: true));
    try {
      await _repo.approveOrder(orderId);
      logger.i('StorageOrderDetailCubit → approveOrder success');
      await load();
    } catch (e, st) {
      logger.e('StorageOrderDetailCubit → approveOrder failed',
          error: e, stackTrace: st);
      emit(StorageOrderDetailError(e.toString()));
    }
  }
}
