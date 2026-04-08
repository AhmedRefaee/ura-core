import 'package:equatable/equatable.dart';
import '../../../shared/models/profile.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthUnauthenticated extends AuthState {}

class AuthPendingApproval extends AuthState {
  final Profile profile;

  const AuthPendingApproval(this.profile);

  @override
  List<Object?> get props => [profile];
}

class AuthAuthenticated extends AuthState {
  final Profile profile;

  const AuthAuthenticated(this.profile);

  @override
  List<Object?> get props => [profile];
}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthPasswordRecovery extends AuthState {}
