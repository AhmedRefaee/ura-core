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

  User? get currentUser => _supabase.auth.currentUser;

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
          .select('id, full_name, phone, role, is_approved, created_at')
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

  Future<AppResult<void>> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      logger.d('signUp → $email | name: $fullName');
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        logger.e('signUp → auth succeeded but user is null');
        return const AppFailure(AppError(
          message: 'فشل إنشاء الحساب. يرجى المحاولة مجدداً.',
          type: AppErrorType.server,
        ));
      }
      logger.d('signUp → inserting profile row for ${user.id}');
      await _supabase.from('profiles').insert({
        'id': user.id,
        'full_name': fullName,
        'phone': phone,
        'role': 'rep',
        'is_approved': false,
      });
      logger.i('signUp → profile row created for $fullName');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('signUp failed', error: e, stackTrace: st);
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
