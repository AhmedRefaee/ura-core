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
  final List<Order> orders;
  const UserOrdersLoaded(this.orders);
  @override
  List<Object?> get props => [orders];
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
      List<Order> orders;
      switch (user.role) {
        case UserRole.rep:
          orders = await _repo.fetchOrdersByRep(user.id);
        case UserRole.storageActor:
          orders = await _repo.fetchOrdersByStorageActor(user.id);
        default:
          // verifier and manager: show orders they created
          orders = await _repo.fetchOrdersByCreator(user.id);
      }
      emit(UserOrdersLoaded(orders));
    } catch (e, st) {
      logger.e('UserOrdersCubit → load failed', error: e, stackTrace: st);
      emit(UserOrdersError(e.toString()));
    }
  }
}
