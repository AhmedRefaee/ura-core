part of '../chat_hub_screen.dart';

/// Reusable chat section — AppBar + tabs + body.
/// Drop this directly into any role home screen's chat nav tab.
/// Reads [ChatThreadsCubit] and [NotificationsBadgeCubit] from context
/// (both must already be provided by the parent home screen).
class ChatHubSection extends StatelessWidget {
  const ChatHubSection({super.key});

  @override
  Widget build(BuildContext context) {
    final canCreate = chatHubCanCreate(context);

    return CollapsingHeaderWrapper(
      title: const Text('المحادثات'),
      actions: [
        if (canCreate)
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'محادثة جديدة',
            onPressed: () => chatHubCreateThread(context),
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
          onPressed: () => context.read<ChatThreadsCubit>().loadThreads(),
        ),
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.push('/notifications'),
            ),
          ),
        ),
      ],
      body: const ChatHubBody(),
    );
  }
}
