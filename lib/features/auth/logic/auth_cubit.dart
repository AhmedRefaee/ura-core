import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../core/logging/app_logger.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;
  late final StreamSubscription _authSubscription;

  AuthCubit(this._repo) : super(AuthInitial()) {
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
    emit(AuthLoading());
    try {
      final user = _repo.currentUser;
      if (user == null) {
        logger.i('AuthCubit → no active session');
        emit(AuthUnauthenticated());
        return;
      }
      final profile = await _repo.fetchProfile(user.id);
      if (profile == null) {
        logger.w('AuthCubit → session exists but no profile row — treating as unauthenticated');
        emit(AuthUnauthenticated());
        return;
      }
      if (!profile.isApproved) {
        logger.i('AuthCubit → user pending approval: ${profile.fullName}');
        emit(AuthPendingApproval(profile));
        return;
      }
      logger.i('AuthCubit → authenticated as ${profile.fullName} [${profile.role}]');
      emit(AuthAuthenticated(profile));
    } catch (e, st) {
      logger.e('AuthCubit → checkSession failed', error: e, stackTrace: st);
      emit(AuthError(_friendlyMessage(e)));
    }
  }

  Future<void> signIn(String email, String password) async {
    logger.d('AuthCubit → signIn: $email');
    emit(AuthLoading());
    try {
      await _repo.signIn(email: email, password: password);
      await checkSession();
    } catch (e, st) {
      logger.e('AuthCubit → signIn failed', error: e, stackTrace: st);
      emit(AuthError(_friendlyMessage(e)));
    }
  }

  Future<void> signUp(String email, String password, String fullName) async {
    logger.d('AuthCubit → signUp: $email');
    emit(AuthLoading());
    try {
      await _repo.signUp(email: email, password: password, fullName: fullName);
      await checkSession();
    } catch (e, st) {
      logger.e('AuthCubit → signUp failed', error: e, stackTrace: st);
      emit(AuthError(_friendlyMessage(e)));
    }
  }

  Future<void> signOut() async {
    logger.i('AuthCubit → signOut');
    await _repo.signOut();
    emit(AuthUnauthenticated());
  }

  Future<void> refreshProfile() async {
    logger.d('AuthCubit → refreshProfile');
    await checkSession();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    logger.d('AuthCubit → sendPasswordResetEmail: $email');
    await _repo.sendPasswordResetEmail(email);
  }

  Future<void> updatePassword(String newPassword) async {
    logger.d('AuthCubit → updatePassword');
    emit(AuthLoading());
    try {
      await _repo.updatePassword(newPassword);
      await checkSession();
    } catch (e, st) {
      logger.e('AuthCubit → updatePassword failed', error: e, stackTrace: st);
      emit(AuthError(_friendlyMessage(e)));
    }
  }

  @override
  Future<void> close() {
    _authSubscription.cancel();
    return super.close();
  }

  String _friendlyMessage(dynamic e) {
    if (e is AuthException) return e.message;
    if (e is PostgrestException) return e.message;
    return 'حدث خطأ غير متوقع';
  }
}
