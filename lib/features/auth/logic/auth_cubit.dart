import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../core/cache/local_profile_source.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/retry_handler.dart';
import '../../../core/notifications/notification_service.dart';
import '../../notifications/logic/chat_badge_cubit.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;
  final LocalProfileSource _localProfile;
  late final StreamSubscription _authSubscription;

  AuthCubit(this._repo, this._localProfile) : super(AuthInitial()) {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        logger.i('AuthCubit → passwordRecovery event received');
        emit(AuthPasswordRecovery());
      }
    });
  }

  Future<void> checkSession() async {
    logger.d('AuthCubit → checkSession');
    final user = _repo.currentUser;
    if (user == null) {
      logger.i('AuthCubit → no active session');
      _localProfile.clear();
      emit(AuthUnauthenticated());
      return;
    }

    // Show cached profile instantly so the home screen appears without a spinner
    final cached = _localProfile.get();
    if (cached != null && cached.isApproved) {
      logger.d('AuthCubit → emitting cached profile for ${cached.fullName}');
      emit(AuthAuthenticated(cached));
    } else {
      emit(AuthLoading());
    }

    final profileResult = await withRetry(() => _repo.fetchProfile(user.id));
    switch (profileResult) {
      case AppSuccess(:final data):
        if (data == null) {
          logger.w('AuthCubit → session exists but no profile row — treating as unauthenticated');
          await _localProfile.clear();
          emit(AuthUnauthenticated());
          return;
        }
        if (!data.isApproved) {
          logger.i('AuthCubit → user pending approval: ${data.fullName}');
          await _localProfile.clear();
          emit(AuthPendingApproval(data));
          return;
        }
        logger.i('AuthCubit → authenticated as ${data.fullName} [${data.role}]');
        await _localProfile.save(data);
        emit(AuthAuthenticated(data));
        await sl<NotificationService>().registerForUser(data.id);
        await sl<NotificationsBadgeCubit>().subscribe();
        await sl<ChatBadgeCubit>().subscribe();
      case AppFailure(:final error):
        logger.e('AuthCubit → checkSession failed: ${error.message}');
        // If we already showed cached data, keep it rather than showing an error
        if (state is! AuthAuthenticated) emit(AuthError(error.message));
    }
  }

  Future<void> signIn(String email, String password) async {
    logger.d('AuthCubit → signIn: $email');
    emit(AuthLoading());
    final result = await _repo.signIn(email: email, password: password);
    switch (result) {
      case AppSuccess():
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → signIn failed: ${error.message}');
        emit(AuthError(error.message));
    }
  }

  Future<void> signUp(String email, String password, String fullName, String phone) async {
    logger.d('AuthCubit → signUp: $email');
    emit(AuthLoading());
    final result = await _repo.signUp(email: email, password: password, fullName: fullName, phone: phone);
    switch (result) {
      case AppSuccess():
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → signUp failed: ${error.message}');
        emit(AuthError(error.message));
    }
  }

  Future<void> signOut() async {
    logger.i('AuthCubit → signOut');
    final userId = _repo.currentUser?.id;
    if (userId != null) {
      await sl<NotificationService>().unregisterForUser(userId);
    }
    await sl<NotificationsBadgeCubit>().cancel();
    await sl<ChatBadgeCubit>().cancel();
    await _localProfile.clear();
    await _repo.signOut();
    emit(AuthUnauthenticated());
  }

  Future<void> refreshProfile() async {
    logger.d('AuthCubit → refreshProfile');
    await checkSession();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    logger.d('AuthCubit → sendPasswordResetEmail: $email');
    final result = await _repo.sendPasswordResetEmail(email);
    if (result is AppFailure<void>) {
      logger.e('AuthCubit → sendPasswordResetEmail failed: ${result.error.message}');
      emit(AuthError(result.error.message));
    }
  }

  Future<void> updatePassword(String newPassword) async {
    logger.d('AuthCubit → updatePassword');
    emit(AuthLoading());
    final result = await _repo.updatePassword(newPassword);
    switch (result) {
      case AppSuccess():
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → updatePassword failed: ${error.message}');
        if (error.type == AppErrorType.sessionExpired) {
          emit(AuthUnauthenticated());
        } else {
          emit(AuthError(error.message));
        }
    }
  }

  @override
  Future<void> close() {
    _authSubscription.cancel();
    return super.close();
  }
}
