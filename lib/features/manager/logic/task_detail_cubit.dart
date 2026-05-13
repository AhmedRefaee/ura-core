import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../data/manager_repository.dart';
import '../../verifier/data/inventory_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class TaskDetailState extends Equatable {
  const TaskDetailState();
  @override
  List<Object?> get props => [];
}

class TaskDetailInitial extends TaskDetailState {}

class TaskDetailLoading extends TaskDetailState {}

class TaskDetailLoaded extends TaskDetailState {
  final Order order;
  final List<AuditLogEntry> auditLog;
  final Map<String, String> receipts;
  final Map<String, InventoryItem> stockItems;
  const TaskDetailLoaded({
    required this.order,
    required this.auditLog,
    required this.receipts,
    this.stockItems = const {},
  });
  @override
  List<Object?> get props => [order, auditLog, receipts, stockItems];
}

class TaskDetailError extends TaskDetailState {
  final String message;
  const TaskDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class TaskDetailDeleted extends TaskDetailState {}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class TaskDetailCubit extends Cubit<TaskDetailState> {
  final ManagerRepository _repo;
  final InventoryRepository _inventoryRepo;
  final String orderId;

  TaskDetailCubit(this._repo, this.orderId, this._inventoryRepo) : super(TaskDetailInitial());

  Future<void> deleteOrder() async {
    logger.d('TaskDetailCubit → deleteOrder: $orderId');
    emit(TaskDetailLoading());
    final result = await _repo.deleteOrder(orderId);
    switch (result) {
      case AppSuccess():
        emit(TaskDetailDeleted());
      case AppFailure(:final error):
        logger.e('TaskDetailCubit → deleteOrder failed: ${error.message}');
        emit(TaskDetailError(error.message));
    }
  }

  Future<void> load() async {
    logger.d('TaskDetailCubit → load: $orderId');
    emit(TaskDetailLoading());

    final results = await Future.wait([
      _repo.fetchOrderDetail(orderId),
      _repo.fetchAuditLog(orderId),
      _repo.fetchReceipts(orderId),
    ]);

    final orderError = results[0].failureOrNull;
    if (orderError != null) {
      logger.e('TaskDetailCubit → load failed: ${orderError.message}');
      emit(TaskDetailError(orderError.message));
      return;
    }
    final auditError = results[1].failureOrNull;
    if (auditError != null) {
      logger.e('TaskDetailCubit → load failed: ${auditError.message}');
      emit(TaskDetailError(auditError.message));
      return;
    }
    final receiptsError = results[2].failureOrNull;
    if (receiptsError != null) {
      logger.e('TaskDetailCubit → load failed: ${receiptsError.message}');
      emit(TaskDetailError(receiptsError.message));
      return;
    }

    final order = (results[0] as AppSuccess<Order>).data;
    final invIds = order.items
        .where((i) => !i.isCustom && i.inventoryId != null)
        .map((i) => i.inventoryId!)
        .toList();

    final stockResult = await _inventoryRepo.fetchItemsByIds(invIds);
    final stockError = stockResult.failureOrNull;
    if (stockError != null) {
      logger.e('TaskDetailCubit → fetchItemsByIds failed: ${stockError.message}');
      emit(TaskDetailError(stockError.message));
      return;
    }

    emit(TaskDetailLoaded(
      order: order,
      auditLog: (results[1] as AppSuccess<List<AuditLogEntry>>).data,
      receipts: (results[2] as AppSuccess<Map<String, String>>).data,
      stockItems: (stockResult as AppSuccess<Map<String, InventoryItem>>).data,
    ));
  }
}
