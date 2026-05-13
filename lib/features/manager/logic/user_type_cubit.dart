import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
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
    final result = await _repo.fetchUsersByRole(role);
    switch (result) {
      case AppSuccess(:final data):
        emit(UserTypeLoaded(data));
      case AppFailure(:final error):
        logger.e('UserTypeCubit → load failed: ${error.message}');
        emit(UserTypeError(error.message));
    }
  }
}
