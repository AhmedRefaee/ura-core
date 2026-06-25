import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/cache/memory_cache.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';

class AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _cache = MemoryCache<String, Profile>(ttl: Duration(minutes: 10));
  final _orgNameCache = MemoryCache<String, String>(ttl: Duration(minutes: 30));

  User? get currentUser => _supabase.auth.currentUser;

  /// Org name is read-only-own under RLS, so this only ever resolves for the
  /// caller's own organization — fine, since every profile shown in the app
  /// (RLS-scoped) belongs to that same organization.
  Future<AppResult<String?>> fetchOrganizationName(String? orgId) async {
    if (orgId == null) return const AppSuccess(null);
    final cached = _orgNameCache.get(orgId);
    if (cached != null) return AppSuccess(cached);
    try {
      final data = await _supabase
          .from('organizations')
          .select('name')
          .eq('id', orgId)
          .maybeSingle();
      final name = data?['name'] as String?;
      if (name != null) _orgNameCache.set(orgId, name);
      return AppSuccess(name);
    } catch (e, st) {
      logger.e('fetchOrganizationName failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  void invalidateProfile(String userId) {
    _cache.invalidate('profile:$userId');
  }

  Future<AppResult<Profile?>> fetchProfile(String userId) async {
    try {
      final cacheKey = 'profile:$userId';
      final cached = _cache.get(cacheKey);
      if (cached != null) {
        logger.d('fetchProfile → cache hit for $userId');
        return AppSuccess(cached);
      }
      
      logger.d('fetchProfile → userId: $userId');
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved, organization_id, created_at')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) {
        logger.w('fetchProfile → no profile row found for $userId');
        return const AppSuccess(null);
      }
      final profile = Profile.fromMap(data);
      _cache.set(cacheKey, profile);
      logger.i('fetchProfile → ${profile.fullName} | role: ${profile.role} | approved: ${profile.isApproved}');
      return AppSuccess(profile);
    } catch (e, st) {
      logger.e('fetchProfile failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      logger.d('signIn → $email');
      await _supabase.auth.signInWithPassword(email: email, password: password);
      logger.i('signIn → success');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('signIn failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Creates the auth account only. The profile row (with role / approval /
  /// organization) is created afterwards by an onboarding RPC — never from the
  /// client — so those privileged fields can't be self-assigned.
  Future<AppResult<void>> signUp({
    required String email,
    required String password,
  }) async {
    try {
      logger.d('signUp → $email');
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user == null) {
        logger.e('signUp → auth succeeded but user is null');
        return const AppFailure(AppError(
          message: 'فشل إنشاء الحساب. يرجى المحاولة مجدداً.',
          type: AppErrorType.server,
        ));
      }
      logger.i('signUp → auth account created for $email');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('signUp failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Runs an onboarding RPC that returns `{success, error?}` and clears the
  /// profile cache so the freshly created row is fetched on next checkSession.
  Future<AppResult<void>> _runOnboardingRpc(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      logger.d('onboarding → $fn');
      final result = await _supabase.rpc(fn, params: params);
      final map = result is Map ? result : <String, dynamic>{};
      if (map['success'] == true) {
        _cache.clear();
        logger.i('onboarding → $fn success');
        return const AppSuccess(null);
      }
      final msg = map['error'] as String? ?? 'تعذّر إكمال العملية';
      logger.w('onboarding → $fn failed: $msg');
      return AppFailure(AppError(message: msg, type: AppErrorType.server));
    } catch (e, st) {
      logger.e('onboarding $fn failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> createOrganization({
    required String orgName,
    required String fullName,
    required String phone,
  }) =>
      _runOnboardingRpc('create_organization_and_owner', {
        'p_org_name': orgName,
        'p_full_name': fullName,
        'p_phone': phone,
      });

  Future<AppResult<void>> joinByCode({
    required String code,
    required String fullName,
    required String phone,
  }) =>
      _runOnboardingRpc('join_organization_by_code', {
        'p_code': code,
        'p_full_name': fullName,
        'p_phone': phone,
      });

  Future<AppResult<void>> joinById({
    required String orgId,
    required String fullName,
    required String phone,
  }) =>
      _runOnboardingRpc('join_organization_by_id', {
        'p_org_id': orgId,
        'p_full_name': fullName,
        'p_phone': phone,
      });

  Future<AppResult<List<({String id, String name})>>> listDiscoverableOrgs(
      String? search) async {
    try {
      final result = await _supabase.rpc('list_discoverable_orgs', params: {
        'p_search': (search == null || search.trim().isEmpty)
            ? null
            : search.trim(),
      });
      final rows = (result as List?) ?? const [];
      final orgs = rows
          .map((r) => (id: r['id'] as String, name: r['name'] as String))
          .toList();
      return AppSuccess(orgs);
    } catch (e, st) {
      logger.e('listDiscoverableOrgs failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> updatePhone(String userId, String phone) async {
    try {
      logger.d('updatePhone → $userId');
      await _supabase.from('profiles').update({'phone': phone}).eq('id', userId);
      _cache.invalidate('profile:$userId');
      logger.i('updatePhone → success');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('updatePhone failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<void> signOut() async {
    logger.d('signOut');
    await _supabase.auth.signOut();
    _cache.clear();
    logger.i('signOut → done');
  }

  Future<AppResult<void>> sendPasswordResetEmail(String email) async {
    try {
      logger.d('sendPasswordResetEmail → $email');
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'ura-core://auth/callback',
      );
      logger.i('sendPasswordResetEmail → email sent');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('sendPasswordResetEmail failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> updatePassword(String newPassword) async {
    try {
      logger.d('updatePassword');
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      logger.i('updatePassword → success');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('updatePassword failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
