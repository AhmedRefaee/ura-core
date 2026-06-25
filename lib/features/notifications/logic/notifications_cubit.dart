import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/app_notification.dart';
import '../data/notifications_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ── States ────────────────────────────────────────────────────────────────────

abstract class NotificationsState extends Equatable {
  const NotificationsState();
  @override
  List<Object?> get props => [];
}

class NotificationsInitial extends NotificationsState {}

class NotificationsLoading extends NotificationsState {}

class NotificationsLoaded extends NotificationsState {
  final List<AppNotification> items;
  const NotificationsLoaded(this.items);
  @override
  List<Object?> get props => [items];
}

class NotificationsError extends NotificationsState {
  final String message;
  const NotificationsError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class NotificationsCubit extends Cubit<NotificationsState>
    with SafeEmit<NotificationsState> {
  final NotificationsRepository _repo;
  RealtimeChannel? _channel;

  NotificationsCubit(this._repo) : super(NotificationsInitial());

  Future<void> load() async {
    logger.d('NotificationsCubit → load');
    safeEmit(NotificationsLoading());
    await _fetch();
  }

  Future<void> _fetch() async {
    if (isClosed) return;
    final result = await _repo.fetchRecent();
    if (isClosed) return;
    switch (result) {
      case AppSuccess(:final data):
        safeEmit(NotificationsLoaded(data));
        _channel ??= Supabase.instance.client
            .channel('notifications-list-$hashCode')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
              callback: (_) => _fetch(),
            )
            .subscribe();
      case AppFailure(:final error):
        logger.e('NotificationsCubit → load failed: ${error.message}');
        safeEmit(NotificationsError(error.message));
    }
  }

  Future<void> deleteNotification(String id) async {
    if (state is! NotificationsLoaded) return;
    final current = (state as NotificationsLoaded).items;
    safeEmit(NotificationsLoaded(current.where((n) => n.id != id).toList()));
    final result = await _repo.deleteNotification(id);
    if (result is AppFailure) {
      logger.e(
        'NotificationsCubit → deleteNotification failed: ${result.error.message}',
      );
      await _fetch();
    }
  }

  Future<void> deleteAllNotifications() async {
    safeEmit(const NotificationsLoaded([]));
    final result = await _repo.deleteAllNotifications();
    if (result is AppFailure) {
      logger.e(
        'NotificationsCubit → deleteAllNotifications failed: ${result.error.message}',
      );
      await _fetch();
    }
  }

  Future<void> markAllRead() async {
    logger.d('NotificationsCubit → markAllRead');
    final result = await _repo.markAllRead();
    if (result is AppFailure) {
      logger.e(
        'NotificationsCubit → markAllRead failed: ${result.error.message}',
      );
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
