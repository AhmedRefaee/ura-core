import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/chat_thread.dart';
import '../data/chat_repository.dart';

/// Bottom sheet that lets the user choose which thread to send an urgent
/// order note to. The verifier's direct thread is always shown at the top
/// as the default option. Returns ({String threadId, String threadTitle})
/// via Navigator.pop, or null if dismissed.
class ChatThreadPickerSheet extends StatefulWidget {
  final String verifierId;
  final String verifierName;

  const ChatThreadPickerSheet({
    super.key,
    required this.verifierId,
    required this.verifierName,
  });

  @override
  State<ChatThreadPickerSheet> createState() => _ChatThreadPickerSheetState();
}

class _ChatThreadPickerSheetState extends State<ChatThreadPickerSheet> {
  final _repo = sl<ChatRepository>();

  bool _loading = true;
  String? _error;
  String? _directThreadId;
  List<ChatThread> _otherThreads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _repo.getOrCreateDirectThread(widget.verifierId),
        _repo.getThreads(),
      ]);
      final directId = results[0] as String;
      final allThreads = results[1] as List<ChatThread>;
      if (mounted) {
        setState(() {
          _directThreadId = directId;
          _otherThreads = allThreads.where((t) => t.id != directId).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _select(String threadId, String threadTitle) {
    Navigator.pop(context, (threadId: threadId, threadTitle: threadTitle));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (_, scrollController) => Column(
        children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.send, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'اختر المحادثة',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'سيتم إرسال الملاحظة العاجلة إلى المحادثة المختارة',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body
          Expanded(child: _buildBody(scrollController)),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Default: direct thread with the verifier
        _DirectThreadTile(
          verifierName: widget.verifierName,
          onTap: () => _select(_directThreadId!, widget.verifierName),
        ),

        // Other threads
        if (_otherThreads.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'محادثات أخرى',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ..._otherThreads.map(
            (t) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  t.title.isNotEmpty ? t.title[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(t.title),
              trailing: t.isDirect
                  ? const Icon(Icons.lock_outline, size: 16, color: Colors.blueGrey)
                  : const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _select(t.id, t.title),
            ),
          ),
        ],
      ],
    );
  }
}

class _DirectThreadTile extends StatelessWidget {
  final String verifierName;
  final VoidCallback onTap;

  const _DirectThreadTile({required this.verifierName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          child: Icon(Icons.person, color: Colors.orange.shade800),
        ),
        title: Text(
          verifierName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('محادثة مباشرة مع الموظف المسؤول'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.orange.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'افتراضي',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade900,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
