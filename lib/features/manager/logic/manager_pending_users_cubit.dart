import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class ManagerPendingUsersState extends Equatable {
  const ManagerPendingUsersState();
  @override
  List<Object?> get props => [];
}

class ManagerPendingUsersInitial extends ManagerPendingUsersState {}

class ManagerPendingUsersLoading extends ManagerPendingUsersState {}

class ManagerPendingUsersLoaded extends ManagerPendingUsersState {
  final List<Profile> users;
  const ManagerPendingUsersLoaded(this.users);
  @override
  List<Object?> get props => [users];
}

class ManagerPendingUsersError extends ManagerPendingUsersState {
  final String message;
  const ManagerPendingUsersError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class ManagerPendingUsersCubit extends Cubit<ManagerPendingUsersState> {
  final ManagerRepository _repo;

  ManagerPendingUsersCubit(this._repo) : super(ManagerPendingUsersInitial());

  Future<void> load() async {
    logger.d('ManagerPendingUsersCubit → load');
    emit(ManagerPendingUsersLoading());
    try {
      final users = await _repo.fetchPendingUsers();
      emit(ManagerPendingUsersLoaded(users));
    } catch (e, st) {
      logger.e('ManagerPendingUsersCubit → load failed', error: e, stackTrace: st);
      emit(ManagerPendingUsersError(e.toString()));
    }
  }

  Future<void> approveUser(String userId, String role) async {
    logger.d('ManagerPendingUsersCubit → approveUser: $userId as $role');
    try {
      await _repo.approveUser(userId, role);
      await load();
    } catch (e, st) {
      logger.e('ManagerPendingUsersCubit → approveUser failed', error: e, stackTrace: st);
      emit(ManagerPendingUsersError(e.toString()));
    }
  }
}
