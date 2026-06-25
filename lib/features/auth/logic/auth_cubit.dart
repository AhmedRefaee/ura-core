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

import '../../../core/logic/safe_emit.dart';

class AuthCubit extends Cubit<AuthState> with SafeEmit<AuthState> {
  final AuthRepository _repo;
  final LocalProfileSource _localProfile;
  late final StreamSubscription _authSubscription;

  /// Set by the pre-auth "create organization" name screen, read by the
  /// post-signup onboarding redirect to decide create-details vs join.
  String? _pendingOrgName;
  String? get pendingOrgName => _pendingOrgName;
  bool get hasPendingOrgCreation => _pendingOrgName != null;
  void setPendingOrgName(String name) => _pendingOrgName = name;

  AuthCubit(this._repo, this._localProfile) : super(AuthInitial()) {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        logger.i('AuthCubit → passwordRecovery event received');
        safeEmit(AuthPasswordRecovery());
      }
    });
  }

  Future<void> checkSession() async {
    logger.d('AuthCubit → checkSession');
    final user = _repo.currentUser;
    if (user == null) {
      logger.i('AuthCubit → no active session');
      _localProfile.clear();
      safeEmit(AuthUnauthenticated());
      return;
    }

    // Hidden platform admin — identified by a server-set JWT claim, has no
    // profile row, routes straight to the admin console.
    if (user.appMetadata['platform_admin'] == true) {
      logger.i('AuthCubit → platform admin session');
      await _localProfile.clear();
      safeEmit(AuthPlatformAdmin());
      return;
    }

    // Show cached profile instantly so the home screen appears without a spinner
    final cached = _localProfile.get();
    if (cached != null && cached.isApproved) {
      logger.d('AuthCubit → emitting cached profile for ${cached.fullName}');
      safeEmit(AuthAuthenticated(cached));
    } else {
      safeEmit(AuthLoading());
    }

    final profileResult = await withRetry(() => _repo.fetchProfile(user.id));
    switch (profileResult) {
      case AppSuccess(:final data):
        if (data == null) {
          logger.i(
            'AuthCubit → session exists but no profile row — needs onboarding',
          );
          await _localProfile.clear();
          safeEmit(AuthNeedsOnboarding());
          return;
        }
        if (!data.isApproved) {
          logger.i('AuthCubit → user pending approval: ${data.fullName}');
          await _localProfile.clear();
          safeEmit(AuthPendingApproval(data));
          return;
        }
        logger.i(
          'AuthCubit → authenticated as ${data.fullName} [${data.role}]',
        );
        await _localProfile.save(data);
        safeEmit(AuthAuthenticated(data));
        await sl<NotificationService>().registerForUser(data.id);
        await sl<NotificationsBadgeCubit>().subscribe();
        await sl<ChatBadgeCubit>().subscribe();
      case AppFailure(:final error):
        logger.e('AuthCubit → checkSession failed: ${error.message}');
        // If we already showed cached data, keep it rather than showing an error
        if (state is! AuthAuthenticated) safeEmit(AuthError(error.message));
    }
  }

  Future<void> signIn(String email, String password) async {
    logger.d('AuthCubit → signIn: $email');
    safeEmit(AuthLoading());
    final result = await _repo.signIn(email: email, password: password);
    switch (result) {
      case AppSuccess():
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → signIn failed: ${error.message}');
        safeEmit(AuthError(error.message));
    }
  }

  Future<void> signUp(String email, String password) async {
    logger.d('AuthCubit → signUp: $email');
    safeEmit(AuthLoading());
    final result = await _repo.signUp(email: email, password: password);
    switch (result) {
      case AppSuccess():
        // No profile row yet → checkSession emits AuthNeedsOnboarding.
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → signUp failed: ${error.message}');
        safeEmit(AuthError(error.message));
    }
  }

  // ── Onboarding: create or join an organization ──────────────────────────────

  Future<void> createOrganization({
    required String fullName,
    required String phone,
  }) async {
    final orgName = _pendingOrgName;
    if (orgName == null) {
      logger.e(
        'AuthCubit → createOrganization called with no pending org name',
      );
      safeEmit(const AuthError('يرجى إدخال اسم المؤسسة أولاً'));
      return;
    }
    safeEmit(AuthLoading());
    final result = await _repo.createOrganization(
      orgName: orgName,
      fullName: fullName,
      phone: phone,
    );
    switch (result) {
      case AppSuccess():
        _pendingOrgName = null;
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → createOrganization failed: ${error.message}');
        safeEmit(AuthError(error.message));
    }
  }

  Future<void> joinByCode({
    required String code,
    required String fullName,
    required String phone,
  }) => _runOnboarding(
    () => _repo.joinByCode(code: code, fullName: fullName, phone: phone),
  );

  Future<void> joinById({
    required String orgId,
    required String fullName,
    required String phone,
  }) => _runOnboarding(
    () => _repo.joinById(orgId: orgId, fullName: fullName, phone: phone),
  );

  Future<AppResult<List<({String id, String name})>>> listDiscoverableOrgs(
    String? search,
  ) => _repo.listDiscoverableOrgs(search);

  Future<void> _runOnboarding(Future<AppResult<void>> Function() action) async {
    safeEmit(AuthLoading());
    final result = await action();
    switch (result) {
      case AppSuccess():
        // Profile now exists → checkSession routes to home or pending.
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → onboarding failed: ${error.message}');
        safeEmit(AuthError(error.message));
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
    _pendingOrgName = null;
    safeEmit(AuthUnauthenticated());
  }

  Future<void> refreshProfile() async {
    logger.d('AuthCubit → refreshProfile');
    final user = _repo.currentUser;
    if (user != null) _repo.invalidateProfile(user.id);
    await checkSession();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    logger.d('AuthCubit → sendPasswordResetEmail: $email');
    final result = await _repo.sendPasswordResetEmail(email);
    if (result is AppFailure<void>) {
      logger.e(
        'AuthCubit → sendPasswordResetEmail failed: ${result.error.message}',
      );
      safeEmit(AuthError(result.error.message));
    }
  }

  Future<void> updatePassword(String newPassword) async {
    logger.d('AuthCubit → updatePassword');
    safeEmit(AuthLoading());
    final result = await _repo.updatePassword(newPassword);
    switch (result) {
      case AppSuccess():
        await checkSession();
      case AppFailure(:final error):
        logger.e('AuthCubit → updatePassword failed: ${error.message}');
        if (error.type == AppErrorType.sessionExpired) {
          safeEmit(AuthUnauthenticated());
        } else {
          safeEmit(AuthError(error.message));
        }
    }
  }

  @override
  Future<void> close() {
    _authSubscription.cancel();
    return super.close();
  }
}
