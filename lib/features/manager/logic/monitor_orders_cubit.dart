import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../data/manager_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class MonitorOrdersState extends Equatable {
  const MonitorOrdersState();
  @override
  List<Object?> get props => [];
}

class MonitorOrdersInitial extends MonitorOrdersState {}

class MonitorOrdersLoading extends MonitorOrdersState {}

class MonitorOrdersLoaded extends MonitorOrdersState {
  final List<Order> activeOrders;
  final List<Order> finishedOrders;
  const MonitorOrdersLoaded({
    required this.activeOrders,
    required this.finishedOrders,
  });
  @override
  List<Object?> get props => [activeOrders, finishedOrders];
}

class MonitorOrdersError extends MonitorOrdersState {
  final String message;
  const MonitorOrdersError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class MonitorOrdersCubit extends Cubit<MonitorOrdersState> {
  final ManagerRepository _repo;

  MonitorOrdersCubit(this._repo) : super(MonitorOrdersInitial());

  Future<void> load() async {
    logger.d('MonitorOrdersCubit → load');
    emit(MonitorOrdersLoading());
    try {
      final active = await _repo.fetchActiveOrders();
      final finished = await _repo.fetchFinishedOrders();
      emit(MonitorOrdersLoaded(activeOrders: active, finishedOrders: finished));
    } catch (e, st) {
      logger.e('MonitorOrdersCubit → load failed', error: e, stackTrace: st);
      emit(MonitorOrdersError(e.toString()));
    }
  }
}
