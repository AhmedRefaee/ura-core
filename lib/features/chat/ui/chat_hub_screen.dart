import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../features/auth/logic/auth_cubit.dart';
import '../../../features/auth/logic/auth_state.dart';
import '../../../shared/models/profile.dart';
import '../logic/chat_threads_cubit.dart';
import 'chat_thread_screen.dart';
import 'create_thread_screen.dart';

class ChatHubScreen extends StatelessWidget {
  const ChatHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChatThreadsCubit>()..loadThreads(),
      child: const _ChatHubView(),
    );
  }
}

class _ChatHubView extends StatelessWidget {
  const _ChatHubView();

  bool _canCreate(BuildContext context) {
    final state = context.read<AuthCubit>().state;
    if (state is! AuthAuthenticated) return false;
    final role = state.profile.role;
    return role == UserRole.verifier || role == UserRole.manager;
  }

  void _createThread(BuildContext context) async {
    final result = await Navigator.push<({String threadId, String title})>(
      context,
      MaterialPageRoute(builder: (_) => const CreateThreadScreen()),
    );
    if (result != null && context.mounted) {
      context.read<ChatThreadsCubit>().loadThreads();
      _openThread(context, result.threadId, result.title);
    }
  }

  void _openThread(
    BuildContext context,
    String id,
    String title, {
    bool isDirect = false,
    String? createdBy,
  }) {
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

  @override
  Widget build(BuildContext context) {
    final canCreate = _canCreate(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المحادثات'),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: 'محادثة جديدة',
              onPressed: () => _createThread(context),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: () => context.read<ChatThreadsCubit>().loadThreads(),
          ),
        ],
      ),
      body: BlocBuilder<ChatThreadsCubit, ChatThreadsState>(
        builder: (context, state) {
          if (state is ChatThreadsLoading || state is ChatThreadsInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ChatThreadsError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: const TextStyle(color: Colors.red)),
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
            if (state.threads.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد محادثات بعد',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    if (canCreate) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _createThread(context),
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء محادثة'),
                      ),
                    ],
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () =>
                  context.read<ChatThreadsCubit>().loadThreads(),
              child: ListView.separated(
                itemCount: state.threads.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) {
                  final thread = state.threads[i];
                  final authState = context.read<AuthCubit>().state;
                  final myName = authState is AuthAuthenticated
                      ? authState.profile.fullName
                      : '';
                  final displayTitle = thread.isDirect
                      ? _resolveDirectTitle(thread.title, myName)
                      : thread.title;
                  return ListTile(
                    leading: CircleAvatar(
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
                    title: Text(
                      displayTitle,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _formatDate(thread.createdAt),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: thread.isDirect
                        ? const Icon(Icons.lock_outline,
                            size: 16, color: Colors.blueGrey)
                        : const Icon(Icons.groups, size: 20, color: Colors.grey),
                    onTap: () => _openThread(
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
      ),
    );
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
}
