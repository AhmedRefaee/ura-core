import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

import '../../../core/logic/safe_emit.dart';
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

  const UserOrdersLoaded({required this.orders, this.doneOrders = const []});

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

class UserOrdersCubit extends Cubit<UserOrdersState>
    with SafeEmit<UserOrdersState> {
  final ManagerRepository _repo;

  UserOrdersCubit(this._repo) : super(UserOrdersInitial()) {
    logger.d('UserOrdersCubit → INITIALIZED');
  }

  Future<void> loadForUser(Profile user) async {
    logger.d('UserOrdersCubit → loadForUser START: ${user.id} (${user.role})');

    if (isClosed) {
      logger.w('UserOrdersCubit → loadForUser ABORTED: cubit already closed');
      return;
    }

    safeEmit(UserOrdersLoading());

    const doneStatuses = {
      OrderStatus.delivered,
      OrderStatus.deliveredToStorage,
    };

    switch (user.role) {
      case UserRole.rep:
        logger.d('UserOrdersCubit → fetching orders for rep: ${user.id}');
        final result = await _repo.fetchOrdersByRep(user.id);
        logger.d('UserOrdersCubit → rep fetch completed, isClosed: $isClosed');

        if (isClosed) {
          logger.w(
            'UserOrdersCubit → ABORTING emit: cubit closed during rep fetch',
          );
          return;
        }

        switch (result) {
          case AppSuccess(:final data):
            logger.d(
              'UserOrdersCubit → emitting UserOrdersLoaded with ${data.length} orders',
            );
            if (!isClosed) {
              safeEmit(
                UserOrdersLoaded(
                  orders: data
                      .where((o) => !doneStatuses.contains(o.status))
                      .toList(),
                  doneOrders: data
                      .where((o) => doneStatuses.contains(o.status))
                      .toList(),
                ),
              );
            }
          case AppFailure(:final error):
            logger.e('UserOrdersCubit → load failed: ${error.message}');
            if (!isClosed) {
              safeEmit(UserOrdersError(error.message));
            }
        }

      case UserRole.storageActor:
        logger.d(
          'UserOrdersCubit → fetching orders for storageActor: ${user.id}',
        );
        final result = await _repo.fetchOrdersByStorageActor(user.id);
        logger.d(
          'UserOrdersCubit → storageActor fetch completed, isClosed: $isClosed',
        );

        if (isClosed) {
          logger.w(
            'UserOrdersCubit → ABORTING emit: cubit closed during storageActor fetch',
          );
          return;
        }

        switch (result) {
          case AppSuccess(:final data):
            logger.d(
              'UserOrdersCubit → emitting UserOrdersLoaded with ${data.length} orders',
            );
            if (!isClosed) {
              safeEmit(
                UserOrdersLoaded(
                  orders: data
                      .where((o) => !doneStatuses.contains(o.status))
                      .toList(),
                  doneOrders: data
                      .where((o) => doneStatuses.contains(o.status))
                      .toList(),
                ),
              );
            }
          case AppFailure(:final error):
            logger.e('UserOrdersCubit → load failed: ${error.message}');
            if (!isClosed) {
              safeEmit(UserOrdersError(error.message));
            }
        }

      default:
        logger.d('UserOrdersCubit → fetching orders for creator: ${user.id}');
        final result = await _repo.fetchOrdersByCreator(user.id);
        logger.d(
          'UserOrdersCubit → creator fetch completed, isClosed: $isClosed',
        );

        if (isClosed) {
          logger.w(
            'UserOrdersCubit → ABORTING emit: cubit closed during creator fetch',
          );
          return;
        }

        switch (result) {
          case AppSuccess(:final data):
            logger.d(
              'UserOrdersCubit → emitting UserOrdersLoaded with ${data.length} orders',
            );
            if (!isClosed) {
              safeEmit(UserOrdersLoaded(orders: data));
            }
          case AppFailure(:final error):
            logger.e('UserOrdersCubit → load failed: ${error.message}');
            if (!isClosed) {
              safeEmit(UserOrdersError(error.message));
            }
        }
    }
  }
}
