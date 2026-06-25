import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../data/notifications_repository.dart';

import '../../../core/logic/safe_emit.dart';

class ChatBadgeCubit extends Cubit<int> with SafeEmit<int> {
  final NotificationsRepository _repo;
  RealtimeChannel? _channel;

  ChatBadgeCubit(this._repo) : super(0);

  Future<void> subscribe() async {
    if (_channel != null) return;
    logger.d('ChatBadgeCubit → subscribe');
    await _fetchCount();
    _channel = Supabase.instance.client
        .channel('chat-badge-$hashCode')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _fetchCount(),
        )
        .subscribe();
  }

  Future<void> _fetchCount() async {
    final result = await _repo.fetchUnreadChatCount();
    switch (result) {
      case AppSuccess(:final data):
        logger.d('ChatBadgeCubit → unread chat: $data');
        if (!isClosed) safeEmit(data);
      case AppFailure(:final error):
        logger.e('ChatBadgeCubit → error: ${error.message}');
    }
  }

  Future<void> clearOnVisit() async {
    final result = await _repo.markAllChatNotificationsRead();
    switch (result) {
      case AppSuccess():
        safeEmit(0);
      case AppFailure(:final error):
        logger.e('ChatBadgeCubit → clearOnVisit error: ${error.message}');
    }
  }

  Future<void> cancel() async {
    await _channel?.unsubscribe();
    _channel = null;
    safeEmit(0);
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
