import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../features/auth/logic/auth_cubit.dart';
import '../../../features/auth/logic/auth_state.dart';
import '../../../features/notifications/data/notifications_repository.dart';
import '../../../shared/models/profile.dart';
import '../logic/chat_threads_cubit.dart';
import 'chat_thread_screen.dart';
import 'create_thread_screen.dart';

// ── Standalone full-screen (used by the /chat deep-link route) ────────────────

class ChatHubScreen extends StatelessWidget {
  const ChatHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChatThreadsCubit>()..loadThreads(),
      child: const _ChatHubScaffold(),
    );
  }
}

class _ChatHubScaffold extends StatefulWidget {
  const _ChatHubScaffold();

  @override
  State<_ChatHubScaffold> createState() => _ChatHubScaffoldState();
}

class _ChatHubScaffoldState extends State<_ChatHubScaffold> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = chatHubCanCreate(context);
    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ابحث في المحادثات...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('المحادثات'),
        actions: [
          if (_showSearch)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'إغلاق البحث',
              onPressed: () => setState(() {
                _showSearch = false;
                _searchQuery = '';
                _searchController.clear();
              }),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'بحث',
              onPressed: () => setState(() => _showSearch = true),
            ),
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
          ],
        ],
      ),
      body: ChatHubBody(filterQuery: _searchQuery),
    );
  }
}

// ── Embeddable body (used inside each role's home screen as a tab) ────────────

class ChatHubBody extends StatelessWidget {
  final String filterQuery;
  const ChatHubBody({super.key, this.filterQuery = ''});

  @override
  Widget build(BuildContext context) {
    final canCreate = chatHubCanCreate(context);

    return BlocBuilder<ChatThreadsCubit, ChatThreadsState>(
      builder: (context, state) {
        if (state is ChatThreadsLoading || state is ChatThreadsInitial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ChatThreadsError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      context.read<ChatThreadsCubit>().loadThreads(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is ChatThreadsLoaded) {
          final threads = filterQuery.isEmpty
              ? state.threads
              : state.threads
                  .where((t) =>
                      t.title
                          .toLowerCase()
                          .contains(filterQuery.toLowerCase()) ||
                      (t.lastMessageContent
                              ?.toLowerCase()
                              .contains(filterQuery.toLowerCase()) ??
                          false))
                  .toList();

          if (threads.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: Theme.of(context).hintColor.withAlpha(150)),
                  const SizedBox(height: 16),
                  Text(
                    filterQuery.isNotEmpty
                        ? 'لا توجد نتائج'
                        : 'لا توجد محادثات بعد',
                    style: TextStyle(fontSize: 18, color: Theme.of(context).hintColor),
                  ),
                  if (canCreate && filterQuery.isEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => chatHubCreateThread(context),
                      icon: const Icon(Icons.add),
                      label: const Text('إنشاء محادثة'),
                    ),
                  ],
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => context.read<ChatThreadsCubit>().loadThreads(),
            child: ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final thread = threads[i];
                final authState = context.read<AuthCubit>().state;
                final myName = authState is AuthAuthenticated
                    ? authState.profile.fullName
                    : '';
                final displayTitle = thread.isDirect
                    ? _resolveDirectTitle(thread.title, myName)
                    : thread.title;
                final hasUnread = thread.unreadCount > 0;
                final dateLabel =
                    _formatDate(thread.lastMessageAt ?? thread.createdAt);

                return ListTile(
                  leading: Badge(
                    isLabelVisible: hasUnread,
                    backgroundColor: Colors.red,
                    label: Text(
                      thread.unreadCount > 9 ? '9+' : '${thread.unreadCount}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        displayTitle.isNotEmpty
                            ? displayTitle[0].toUpperCase()
                            : '?',
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
                      fontWeight:
                          hasUnread ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  subtitle: thread.lastMessageContent != null
                      ? Text(
                          '${thread.lastMessageSenderName ?? ''}: ${thread.lastMessageContent!}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: hasUnread ? null : Theme.of(context).hintColor,
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
                              : Colors.grey,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      thread.isDirect
                          ? const Icon(Icons.lock_outline,
                              size: 16, color: Colors.blueGrey)
                          : const Icon(Icons.groups,
                              size: 20, color: Colors.grey),
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
              },
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ── Shared helpers (used by both ChatHubScreen and home screens) ──────────────

bool chatHubCanCreate(BuildContext context) {
  final state = context.read<AuthCubit>().state;
  if (state is! AuthAuthenticated) return false;
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

String _resolveDirectTitle(String title, String myName) {
  final parts = title.split(' — ');
  if (parts.length != 2) return title;
  final a = parts[0].trim(), b = parts[1].trim();
  return a == myName ? b : (b == myName ? a : title);
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
  if (diff.inDays == 1) return 'أمس';
  return '${dt.day}/${dt.month}/${dt.year}';
}
