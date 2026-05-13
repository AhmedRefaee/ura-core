import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../data/notifications_repository.dart';

class NotificationsBadgeCubit extends Cubit<int> {
  final NotificationsRepository _repo;
  RealtimeChannel? _channel;

  NotificationsBadgeCubit(this._repo) : super(0);

  Future<void> subscribe() async {
    if (_channel != null) return;
    logger.d('NotificationsBadgeCubit → subscribe');
    await _fetchCount();
    _channel = Supabase.instance.client
        .channel('notifications-badge-$hashCode')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _fetchCount(),
        )
        .subscribe();
  }

  Future<void> _fetchCount() async {
    final result = await _repo.fetchUnreadCount();
    switch (result) {
      case AppSuccess(:final data):
        logger.d('NotificationsBadgeCubit → unread: $data');
        emit(data);
      case AppFailure(:final error):
        logger.e('NotificationsBadgeCubit → error: ${error.message}');
    }
  }

  Future<void> cancel() async {
    await _channel?.unsubscribe();
    _channel = null;
    emit(0);
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
