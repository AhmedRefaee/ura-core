import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';

class AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Future<Profile?> fetchProfile(String userId) async {
    logger.d('fetchProfile → userId: $userId');
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data == null) {
      logger.w('fetchProfile → no profile row found for $userId');
      return null;
    }
    final profile = Profile.fromMap(data);
    logger.i('fetchProfile → ${profile.fullName} | role: ${profile.role} | approved: ${profile.isApproved}');
    return profile;
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    logger.d('signIn → $email');
    await _supabase.auth.signInWithPassword(email: email, password: password);
    logger.i('signIn → success');
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    logger.d('signUp → $email | name: $fullName');
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      logger.e('signUp → auth succeeded but user is null (email confirmation may be on)');
      throw const AuthException('فشل إنشاء الحساب. يرجى المحاولة مجدداً.');
    }
    logger.d('signUp → inserting profile row for ${user.id}');
    await _supabase.from('profiles').insert({
      'id': user.id,
      'full_name': fullName,
      'role': 'rep',
      'is_approved': false,
    });
    logger.i('signUp → profile row created for $fullName');
  }

  Future<void> signOut() async {
    logger.d('signOut');
    await _supabase.auth.signOut();
    logger.i('signOut → done');
  }

  Future<void> sendPasswordResetEmail(String email) async {
    logger.d('sendPasswordResetEmail → $email');
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: 'ura-core://auth/callback',
    );
    logger.i('sendPasswordResetEmail → email sent');
  }

  Future<void> updatePassword(String newPassword) async {
    logger.d('updatePassword');
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    logger.i('updatePassword → success');
  }
}
