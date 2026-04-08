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

// ── Cubit ─────────────────────────────────────────────────────────────────────

class TaskDetailCubit extends Cubit<TaskDetailState> {
  final ManagerRepository _repo;
  final String orderId;

  TaskDetailCubit(this._repo, this.orderId) : super(TaskDetailInitial());

  Future<void> load() async {
    logger.d('TaskDetailCubit → load: $orderId');
    emit(TaskDetailLoading());
    try {
      final order = await _repo.fetchOrderDetail(orderId);
      final auditLog = await _repo.fetchAuditLog(orderId);
      emit(TaskDetailLoaded(order: order, auditLog: auditLog));
    } catch (e, st) {
      logger.e('TaskDetailCubit → load failed', error: e, stackTrace: st);
      emit(TaskDetailError(e.toString()));
    }
  }
}
