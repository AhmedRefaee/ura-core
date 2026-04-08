import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';
import '../data/order_repository.dart';

abstract class PendingUsersState extends Equatable {
  const PendingUsersState();
  @override
  List<Object?> get props => [];
}

class PendingUsersInitial extends PendingUsersState {}

class PendingUsersLoading extends PendingUsersState {}

class PendingUsersLoaded extends PendingUsersState {
  final List<Profile> users;
  const PendingUsersLoaded(this.users);
  @override
  List<Object?> get props => [users];
}

class PendingUsersError extends PendingUsersState {
  final String message;
  const PendingUsersError(this.message);
  @override
  List<Object?> get props => [message];
}

class PendingUsersCubit extends Cubit<PendingUsersState> {
  final OrderRepository _repo;

  PendingUsersCubit(this._repo) : super(PendingUsersInitial());

  Future<void> loadPendingUsers() async {
    logger.d('PendingUsersCubit → loadPendingUsers');
    emit(PendingUsersLoading());
    try {
      final users = await _repo.fetchPendingUsers();
      emit(PendingUsersLoaded(users));
    } catch (e, st) {
      logger.e('PendingUsersCubit → load failed', error: e, stackTrace: st);
      emit(PendingUsersError(e.toString()));
    }
  }

  Future<void> approveUser(String userId, String role) async {
    logger.d('PendingUsersCubit → approveUser: $userId as $role');
    try {
      await _repo.approveUser(userId, role);
      await loadPendingUsers();
    } catch (e, st) {
      logger.e('PendingUsersCubit → approveUser failed', error: e, stackTrace: st);
      emit(PendingUsersError(e.toString()));
    }
  }
}
