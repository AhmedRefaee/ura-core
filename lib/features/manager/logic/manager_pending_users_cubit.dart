import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

import '../../../core/logic/safe_emit.dart';
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

class ManagerPendingUsersCubit extends Cubit<ManagerPendingUsersState>
    with SafeEmit<ManagerPendingUsersState> {
  final ManagerRepository _repo;
  RealtimeChannel? _channel;

  ManagerPendingUsersCubit(this._repo) : super(ManagerPendingUsersInitial());

  Future<void> load() async {
    logger.d('ManagerPendingUsersCubit → load');
    safeEmit(ManagerPendingUsersLoading());
    await _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    final result = await _repo.fetchPendingUsers();
    switch (result) {
      case AppSuccess(:final data):
        safeEmit(ManagerPendingUsersLoaded(data));
        _channel ??= Supabase.instance.client
            .channel('pending-users-$hashCode')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'profiles',
              callback: (_) => _fetchUsers(),
            )
            .subscribe();
      case AppFailure(:final error):
        logger.e('ManagerPendingUsersCubit → load failed: ${error.message}');
        safeEmit(ManagerPendingUsersError(error.message));
    }
  }

  Future<void> approveUser(String userId, String role) async {
    logger.d('ManagerPendingUsersCubit → approveUser: $userId as $role');
    final result = await _repo.approveUser(userId, role);
    switch (result) {
      case AppSuccess():
        break;
      case AppFailure(:final error):
        logger.e(
          'ManagerPendingUsersCubit → approveUser failed: ${error.message}',
        );
        safeEmit(ManagerPendingUsersError(error.message));
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
