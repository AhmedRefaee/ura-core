part of '../chat_hub_screen.dart';

class _RoleSection extends StatelessWidget {
  final UserRole role;
  final List<Profile> profiles;

  const _RoleSection({required this.role, required this.profiles});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      title: Text(
        '${_roleSectionLabel(role)} (${profiles.length})',
        style: AppTextStyles.titleSmall.copyWith(fontWeight: FontWeight.w600),
      ),
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.horizontalLarge,
      ),
      children: profiles.map((profile) {
        return _DirectoryUserTile(profile: profile);
      }).toList(),
    );
  }
}

class _DirectoryUserTile extends StatefulWidget {
  final Profile profile;

  const _DirectoryUserTile({required this.profile});

  @override
  State<_DirectoryUserTile> createState() => _DirectoryUserTileState();
}

class _DirectoryUserTileState extends State<_DirectoryUserTile> {
  bool _loading = false;

  Future<void> _openChat() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    final repo = sl<ChatRepository>();
    final result = await repo.getOrCreateDirectThread(widget.profile.id);
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    switch (result) {
      case AppSuccess(:final data):
        chatHubOpenThread(
          context,
          data,
          widget.profile.fullName,
          isDirect: true,
        );
        context.read<ChatThreadsCubit>().loadThreads();
      case AppFailure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile.fullName;

    return AppListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.horizontalXXLarge,
        vertical: AppSpacing.verticalSmall,
      ),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      title: Text(name),
      subtitle: Text(_roleLabel(widget.profile.role)),
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_left, color: AppColors.iconSecondary),
      onTap: _openChat,
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final ChatThread chatThread;

  const _ThreadTile({required ChatThread thread}) : chatThread = thread;

  @override
  Widget build(BuildContext context) {
    final thread = chatThread;
    final displayTitle = thread.isDirect
        ? (thread.otherParticipantName ?? thread.title)
        : thread.title;
    final hasUnread = thread.unreadCount > 0;
    final dateLabel = _formatDate(thread.lastMessageAt ?? thread.createdAt);

    return AppListTile(
      leading: NotificationDot(
        isVisible: hasUnread,
        child: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            displayTitle.isNotEmpty ? displayTitle[0].toUpperCase() : '?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        displayTitle,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: thread.lastMessageContent != null
          ? Text(
              '${thread.lastMessageSenderName ?? ''}: ${thread.lastMessageContent!}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                color: hasUnread ? null : AppColors.textTertiary,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            dateLabel,
            style: TextStyle(
              fontSize: 11,
              color: hasUnread
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.textTertiary,
              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          thread.isDirect
              ? const Icon(Icons.lock_outline, size: 16, color: Colors.blueGrey)
              : const Icon(Icons.groups, size: 20, color: Colors.grey),
        ],
      ),
      onTap: () => chatHubOpenThread(
        context,
        thread.id,
        displayTitle,
        isDirect: thread.isDirect,
        createdBy: thread.createdBy,
      ),
    );
  }
}
