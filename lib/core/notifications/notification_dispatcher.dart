import 'package:supabase_flutter/supabase_flutter.dart';
import '../logging/app_logger.dart';

class NotificationDispatcher {
  static final _supabase = Supabase.instance.client;

  static Future<void> send({
    required List<String> userIds,
    required String title,
    required String body,
    String? route,
  }) async {
    if (userIds.isEmpty) return;
    logger.d('NotificationDispatcher → send to ${userIds.length} users: $title');
    try {
      await _supabase.functions.invoke('send-notification', body: {
        'user_ids': userIds,
        'title': title,
        'body': body,
        'route': route,
      });
    } catch (e) {
      logger.w('NotificationDispatcher → failed: $e');
    }
  }

  static Future<List<String>> userIdsByRole(String role) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('id')
          .eq('role', role)
          .eq('is_approved', true);
      return (data as List).map((e) => e['id'] as String).toList();
    } catch (e) {
      logger.w('NotificationDispatcher → userIdsByRole failed: $e');
      return [];
    }
  }
}
