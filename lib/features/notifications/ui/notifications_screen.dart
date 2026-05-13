import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/di/injection.dart';
import '../data/notifications_repository.dart';
import '../logic/notifications_badge_cubit.dart';
import '../logic/notifications_cubit.dart';
import '../../../shared/models/app_notification.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          BlocBuilder<NotificationsCubit, NotificationsState>(
            builder: (context, state) {
              if (state is! NotificationsLoaded || state.items.isEmpty) {
                return const SizedBox.shrink();
              }
              final loaded = state;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loaded.items.any((n) => !n.isRead))
                    TextButton(
                      onPressed: () {
                        context.read<NotificationsCubit>().markAllRead();
                        sl<NotificationsBadgeCubit>().cancel();
                        sl<NotificationsBadgeCubit>().subscribe();
                      },
                      child: const Text('تحديد الكل كمقروء'),
                    ),
                  TextButton(
                    onPressed: () =>
                        context.read<NotificationsCubit>().deleteAllNotifications(),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('حذف الكل'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<NotificationsCubit, NotificationsState>(
        builder: (context, state) {
          if (state is NotificationsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is NotificationsError) {
            return Center(child: Text(state.message));
          }
          if (state is NotificationsLoaded) {
            if (state.items.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('لا توجد إشعارات', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => context.read<NotificationsCubit>().load(),
              child: ListView.separated(
                itemCount: state.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final n = state.items[index];
                  return _NotificationTile(notification: n);
                },
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.horizontal,
      onDismissed: (_) =>
          context.read<NotificationsCubit>().deleteNotification(notification.id),
      background: const _DeleteBackground(alignment: Alignment.centerLeft),
      secondaryBackground: const _DeleteBackground(alignment: Alignment.centerRight),
      child: ListTile(
        tileColor: unread
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15)
            : null,
        leading: CircleAvatar(
          backgroundColor: unread
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade300,
          child: Icon(
            Icons.notifications_outlined,
            color: unread ? Colors.white : Colors.grey,
            size: 20,
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              timeago.format(notification.createdAt, locale: 'ar'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () async {
          if (!notification.isRead) {
            sl<NotificationsRepository>().markRead(notification.id).ignore();
          }
          if (notification.actionRoute != null && context.mounted) {
            context.push(notification.actionRoute!);
          }
        },
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  final Alignment alignment;
  const _DeleteBackground({required this.alignment});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.red.shade600,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
    );
  }
}
