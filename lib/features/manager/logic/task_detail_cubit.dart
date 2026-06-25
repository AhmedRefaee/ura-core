import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../data/manager_repository.dart';
import '../../verifier/data/order_repository.dart';

import '../../../core/logic/safe_emit.dart';
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
  const TaskDetailLoaded({required this.order, required this.auditLog});
  @override
  List<Object?> get props => [order, auditLog];
}

class TaskDetailError extends TaskDetailState {
  final String message;
  const TaskDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class TaskDetailDeleted extends TaskDetailState {}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class TaskDetailCubit extends Cubit<TaskDetailState>
    with SafeEmit<TaskDetailState> {
  final ManagerRepository _repo;
  final OrderRepository _verifierRepo;
  final String orderId;
  final bool useVerifierRepository;

  TaskDetailCubit(
    this._repo,
    this.orderId,
    this._verifierRepo, {
    this.useVerifierRepository = false,
  }) : super(TaskDetailInitial());

  Future<void> deleteOrder() async {
    logger.d('TaskDetailCubit → deleteOrder: $orderId');
    safeEmit(TaskDetailLoading());
    final result = await _repo.deleteOrder(orderId);
    switch (result) {
      case AppSuccess():
        safeEmit(TaskDetailDeleted());
      case AppFailure(:final error):
        logger.e('TaskDetailCubit → deleteOrder failed: ${error.message}');
        safeEmit(TaskDetailError(error.message));
    }
  }

  Future<void> load() async {
    logger.d('TaskDetailCubit → load: $orderId');
    safeEmit(TaskDetailLoading());

    final results = await Future.wait([
      useVerifierRepository
          ? _verifierRepo.fetchOrderDetail(orderId)
          : _repo.fetchOrderDetail(orderId),
      useVerifierRepository
          ? _verifierRepo.fetchAuditLog(orderId)
          : _repo.fetchAuditLog(orderId),
    ]);

    if (isClosed) return;

    final orderError = results[0].failureOrNull;
    if (orderError != null) {
      logger.e('TaskDetailCubit → load failed: ${orderError.message}');
      safeEmit(TaskDetailError(orderError.message));
      return;
    }
    final auditError = results[1].failureOrNull;
    if (auditError != null) {
      logger.e('TaskDetailCubit → load failed: ${auditError.message}');
      safeEmit(TaskDetailError(auditError.message));
      return;
    }

    final order = (results[0] as AppSuccess<Order>).data;

    safeEmit(
      TaskDetailLoaded(
        order: order,
        auditLog: (results[1] as AppSuccess<List<AuditLogEntry>>).data,
      ),
    );
  }
}
