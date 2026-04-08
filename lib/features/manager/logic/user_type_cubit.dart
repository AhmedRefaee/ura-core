import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class UserTypeState extends Equatable {
  const UserTypeState();
  @override
  List<Object?> get props => [];
}

class UserTypeInitial extends UserTypeState {}

class UserTypeLoading extends UserTypeState {}

class UserTypeLoaded extends UserTypeState {
  final List<Profile> users;
  const UserTypeLoaded(this.users);
  @override
  List<Object?> get props => [users];
}

class UserTypeError extends UserTypeState {
  final String message;
  const UserTypeError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class UserTypeCubit extends Cubit<UserTypeState> {
  final ManagerRepository _repo;

  UserTypeCubit(this._repo) : super(UserTypeInitial());

  Future<void> load(String role) async {
    logger.d('UserTypeCubit → load: $role');
    emit(UserTypeLoading());
    try {
      final users = await _repo.fetchUsersByRole(role);
      emit(UserTypeLoaded(users));
    } catch (e, st) {
      logger.e('UserTypeCubit → load failed', error: e, stackTrace: st);
      emit(UserTypeError(e.toString()));
    }
  }
}
