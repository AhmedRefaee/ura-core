import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
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
  /// Active / in-progress orders (or all orders for non-storage roles).
  final List<Order> orders;

  /// Completed orders — only populated for the storageActor role.
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
    try {
      const doneStatuses = {
        OrderStatus.delivered,
        OrderStatus.deliveredToStorage,
      };

      switch (user.role) {
        case UserRole.rep:
          final all = await _repo.fetchOrdersByRep(user.id);
          emit(UserOrdersLoaded(
            orders:
                all.where((o) => !doneStatuses.contains(o.status)).toList(),
            doneOrders:
                all.where((o) => doneStatuses.contains(o.status)).toList(),
          ));

        case UserRole.storageActor:
          final all = await _repo.fetchOrdersByStorageActor(user.id);
          emit(UserOrdersLoaded(
            orders:
                all.where((o) => !doneStatuses.contains(o.status)).toList(),
            doneOrders:
                all.where((o) => doneStatuses.contains(o.status)).toList(),
          ));

        default:
          // verifier and manager: show orders they created
          final orders = await _repo.fetchOrdersByCreator(user.id);
          emit(UserOrdersLoaded(orders: orders));
      }
    } catch (e, st) {
      logger.e('UserOrdersCubit → load failed', error: e, stackTrace: st);
      emit(UserOrdersError(e.toString()));
    }
  }
}
