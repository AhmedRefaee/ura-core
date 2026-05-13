import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/app_notification.dart';

class NotificationsRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  Future<AppResult<List<AppNotification>>> fetchRecent() async {
    try {
      logger.d('NotificationsRepository → fetchRecent (non-chat)');
      final uid = _userId;
      if (uid == null) return const AppSuccess([]);
      final data = await _supabase
          .from('notifications')
          .select('id, title, body, action_route, is_read, created_at')
          .eq('user_id', uid)
          .not('action_route', 'ilike', '/chat%')
          .order('created_at', ascending: false)
          .limit(50);
      final items = (data as List)
          .map((e) => AppNotification.fromMap(e as Map<String, dynamic>))
          .toList();
      return AppSuccess(items);
    } catch (e, st) {
      logger.e('NotificationsRepository → fetchRecent failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> markChatThreadNotificationsRead(String threadId) async {
    try {
      logger.d('NotificationsRepository → markChatThreadNotificationsRead: $threadId');
      final uid = _userId;
      if (uid == null) return const AppSuccess(null);
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false)
          .eq('action_route', '/chat/$threadId');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('NotificationsRepository → markChatThreadNotificationsRead failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<int>> fetchUnreadCount() async {
    try {
      logger.d('NotificationsRepository → fetchUnreadCount (non-chat)');
      final uid = _userId;
      if (uid == null) return const AppSuccess(0);
      final all = await _fetchUnreadRaw(uid);
      final chat = await _fetchUnreadChatRaw(uid);
      return AppSuccess((all - chat).clamp(0, all));
    } catch (e, st) {
      logger.e('NotificationsRepository → fetchUnreadCount failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<int>> fetchUnreadChatCount() async {
    try {
      logger.d('NotificationsRepository → fetchUnreadChatCount');
      final uid = _userId;
      if (uid == null) return const AppSuccess(0);
      return AppSuccess(await _fetchUnreadChatRaw(uid));
    } catch (e, st) {
      logger.e('NotificationsRepository → fetchUnreadChatCount failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> markAllChatNotificationsRead() async {
    try {
      logger.d('NotificationsRepository → markAllChatNotificationsRead');
      final uid = _userId;
      if (uid == null) return const AppSuccess(null);
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false)
          .ilike('action_route', '/chat%');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('NotificationsRepository → markAllChatNotificationsRead failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> markAllRead() async {
    try {
      logger.d('NotificationsRepository → markAllRead');
      final uid = _userId;
      if (uid == null) return const AppSuccess(null);
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('NotificationsRepository → markAllRead failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> markRead(String id) async {
    try {
      logger.d('NotificationsRepository → markRead: $id');
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('NotificationsRepository → markRead failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteNotification(String id) async {
    try {
      logger.d('NotificationsRepository → deleteNotification: $id');
      await _supabase.from('notifications').delete().eq('id', id);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('NotificationsRepository → deleteNotification failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteAllNotifications() async {
    try {
      logger.d('NotificationsRepository → deleteAllNotifications');
      final uid = _userId;
      if (uid == null) return const AppSuccess(null);
      await _supabase.from('notifications').delete().eq('user_id', uid);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('NotificationsRepository → deleteAllNotifications failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<int> _fetchUnreadRaw(String uid) async {
    final data = await _supabase
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false);
    return (data as List).length;
  }

  Future<int> _fetchUnreadChatRaw(String uid) async {
    final data = await _supabase
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false)
        .ilike('action_route', '/chat%');
    return (data as List).length;
  }
}
