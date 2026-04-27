import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../data/manager_repository.dart';

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
  const TaskDetailLoaded({
    required this.order,
    required this.auditLog,
    required this.receipts,
  });
  @override
  List<Object?> get props => [order, auditLog, receipts];
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
  final String orderId;

  TaskDetailCubit(this._repo, this.orderId) : super(TaskDetailInitial());

  Future<void> deleteOrder() async {
    logger.d('TaskDetailCubit → deleteOrder: $orderId');
    emit(TaskDetailLoading());
    try {
      await _repo.deleteOrder(orderId);
      emit(TaskDetailDeleted());
    } catch (e, st) {
      logger.e('TaskDetailCubit → deleteOrder failed', error: e, stackTrace: st);
      emit(TaskDetailError(e.toString()));
    }
  }

  Future<void> load() async {
    logger.d('TaskDetailCubit → load: $orderId');
    emit(TaskDetailLoading());
    try {
      final results = await Future.wait([
        _repo.fetchOrderDetail(orderId),
        _repo.fetchAuditLog(orderId),
        _repo.fetchReceipts(orderId),
      ]);
      final order = results[0] as Order;
      final auditLog = results[1] as List<AuditLogEntry>;
      final receipts = results[2] as Map<String, String>;
      emit(TaskDetailLoaded(
        order: order,
        auditLog: auditLog,
        receipts: receipts,
      ));
    } catch (e, st) {
      logger.e('TaskDetailCubit → load failed', error: e, stackTrace: st);
      emit(TaskDetailError(e.toString()));
    }
  }
}
