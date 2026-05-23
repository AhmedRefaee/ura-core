part of '../chat_hub_screen.dart';

bool chatHubCanCreate(BuildContext context) {
  final state = context.read<AuthCubit>().state;
  if (state is! AuthAuthenticated) {
    return false;
  }
  final role = state.profile.role;
  return role == UserRole.verifier || role == UserRole.manager;
}

void chatHubCreateThread(BuildContext context) async {
  final result = await Navigator.push<({String threadId, String title})>(
    context,
    MaterialPageRoute(builder: (_) => const CreateThreadScreen()),
  );
  if (result != null && context.mounted) {
    context.read<ChatThreadsCubit>().loadThreads();
    chatHubOpenThread(context, result.threadId, result.title);
  }
}

void chatHubOpenThread(
  BuildContext context,
  String id,
  String title, {
  bool isDirect = false,
  String? createdBy,
}) {
  sl<NotificationsRepository>().markChatThreadNotificationsRead(id).ignore();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatThreadScreen(
        threadId: id,
        threadTitle: title,
        isDirect: isDirect,
        createdBy: createdBy,
      ),
    ),
  ).then((_) {
    if (context.mounted) {
      context.read<ChatThreadsCubit>().loadThreads();
    }
  });
}

String _roleSectionLabel(UserRole role) => switch (role) {
  UserRole.manager => 'المدراء',
  UserRole.verifier => 'موظفو التحقق',
  UserRole.storageActor => 'عمال المخزن',
  UserRole.rep => 'المندوبون',
};

String _roleLabel(UserRole? role) => switch (role) {
  UserRole.manager => 'مدير',
  UserRole.verifier => 'موظف تحقق',
  UserRole.storageActor => 'مخزن',
  UserRole.rep => 'مندوب',
  null => '',
};

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) {
    return 'الآن';
  }
  if (diff.inMinutes < 60) {
    return 'منذ ${diff.inMinutes} د';
  }
  if (diff.inHours < 24) {
    return 'منذ ${diff.inHours} س';
  }
  if (diff.inDays == 1) {
    return 'أمس';
  }
  return '${dt.day}/${dt.month}/${dt.year}';
}
