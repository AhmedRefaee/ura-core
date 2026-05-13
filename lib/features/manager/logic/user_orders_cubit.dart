import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class UserOrdersState extends Equatable {
  const UserOrdersState();
  @override
  List<Object?> get props => [];
}

class UserOrdersInitial extends UserOrdersState {}

class UserOrdersLoading extends UserOrdersState {}

class UserOrdersLoaded extends UserOrdersState {
  final List<Order> orders;
  final List<Order> doneOrders;

  const UserOrdersLoaded({
    required this.orders,
    this.doneOrders = const [],
  });

  @override
  List<Object?> get props => [orders, doneOrders];
}

class UserOrdersError extends UserOrdersState {
  final String message;
  const UserOrdersError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class UserOrdersCubit extends Cubit<UserOrdersState> {
  final ManagerRepository _repo;

  UserOrdersCubit(this._repo) : super(UserOrdersInitial());

  Future<void> loadForUser(Profile user) async {
    logger.d('UserOrdersCubit → loadForUser: ${user.id} (${user.role})');
    emit(UserOrdersLoading());

    const doneStatuses = {
      OrderStatus.delivered,
      OrderStatus.deliveredToStorage,
    };

    switch (user.role) {
      case UserRole.rep:
        final result = await _repo.fetchOrdersByRep(user.id);
        switch (result) {
          case AppSuccess(:final data):
            emit(UserOrdersLoaded(
              orders: data.where((o) => !doneStatuses.contains(o.status)).toList(),
              doneOrders: data.where((o) => doneStatuses.contains(o.status)).toList(),
            ));
          case AppFailure(:final error):
            logger.e('UserOrdersCubit → load failed: ${error.message}');
            emit(UserOrdersError(error.message));
        }

      case UserRole.storageActor:
        final result = await _repo.fetchOrdersByStorageActor(user.id);
        switch (result) {
          case AppSuccess(:final data):
            emit(UserOrdersLoaded(
              orders: data.where((o) => !doneStatuses.contains(o.status)).toList(),
              doneOrders: data.where((o) => doneStatuses.contains(o.status)).toList(),
            ));
          case AppFailure(:final error):
            logger.e('UserOrdersCubit → load failed: ${error.message}');
            emit(UserOrdersError(error.message));
        }

      default:
        final result = await _repo.fetchOrdersByCreator(user.id);
        switch (result) {
          case AppSuccess(:final data):
            emit(UserOrdersLoaded(orders: data));
          case AppFailure(:final error):
            logger.e('UserOrdersCubit → load failed: ${error.message}');
            emit(UserOrdersError(error.message));
        }
    }
  }
}
