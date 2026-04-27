import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../logic/chat_threads_cubit.dart';

/// Returns the selected thread ID (String) via Navigator.pop,
/// or null if the user cancelled.
class ChatPickerScreen extends StatelessWidget {
  const ChatPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChatThreadsCubit>()..loadThreads(),
      child: const _ChatPickerView(),
    );
  }
}

class _ChatPickerView extends StatefulWidget {
  const _ChatPickerView();

  @override
  State<_ChatPickerView> createState() => _ChatPickerViewState();
}

class _ChatPickerViewState extends State<_ChatPickerView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _createNew(BuildContext context) async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('محادثة جديدة'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم المحادثة',
            hintText: 'مثال: دعم التوصيل',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final t = titleController.text.trim();
              if (t.isNotEmpty) Navigator.pop(context, t);
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    if (title != null && context.mounted) {
      final id = await context.read<ChatThreadsCubit>().createThread(title);
      if (id != null && context.mounted) {
        Navigator.pop(context, id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختر محادثة'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'بحث...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),

          // Create new button
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('إنشاء محادثة جديدة'),
            onTap: () => _createNew(context),
          ),
          const Divider(height: 1),

          // Thread list
          Expanded(
            child: BlocBuilder<ChatThreadsCubit, ChatThreadsState>(
              builder: (context, state) {
                if (state is ChatThreadsLoading || state is ChatThreadsInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is ChatThreadsError) {
                  return Center(
                    child: Text(
                      state.message,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (state is ChatThreadsLoaded) {
                  final filtered = _query.isEmpty
                      ? state.threads
                      : state.threads
                          .where((t) => t.title.toLowerCase().contains(_query))
                          .toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد محادثات',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final thread = filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            thread.title.isNotEmpty
                                ? thread.title[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(thread.title),
                        subtitle: Text(
                          _formatDate(thread.createdAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => Navigator.pop(context, thread.id),
                        trailing: const Icon(Icons.chevron_right),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'اليوم';
    if (diff.inDays == 1) return 'أمس';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
