import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/profile.dart';
import '../data/chat_repository.dart';

class CreateThreadScreen extends StatefulWidget {
  const CreateThreadScreen({super.key});

  @override
  State<CreateThreadScreen> createState() => _CreateThreadScreenState();
}

class _CreateThreadScreenState extends State<CreateThreadScreen> {
  final _titleController = TextEditingController();
  final _repo = sl<ChatRepository>();

  List<Profile> _users = [];
  final Set<String> _selected = {};
  bool _loadingUsers = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _repo.getUsers();
      if (mounted) setState(() { _users = users; _loadingUsers = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingUsers = false; });
    }
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المجموعة')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final threadId = await _repo.createThread(title);
      await Future.wait(_selected.map((uid) => _repo.addParticipant(threadId, uid)));
      if (mounted) Navigator.pop(context, (threadId: threadId, title: title));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محادثة جديدة'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إنشاء'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم المجموعة',
                hintText: 'مثال: دعم التوصيل',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'إضافة أعضاء${_selected.isEmpty ? '' : ' (${_selected.length})'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    if (_loadingUsers) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadUsers, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(child: Text('لا يوجد مستخدمون', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final user = _users[i];
        final checked = _selected.contains(user.id);
        return CheckboxListTile(
          value: checked,
          onChanged: (_) => setState(() {
            if (checked) { _selected.remove(user.id); }
            else { _selected.add(user.id); }
          }),
          title: Text(user.fullName),
          subtitle: Text(_roleLabel(user.role)),
          secondary: CircleAvatar(
            child: Text(user.fullName.isNotEmpty ? user.fullName[0] : '?'),
          ),
          controlAffinity: ListTileControlAffinity.trailing,
        );
      },
    );
  }

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.verifier: return 'موظف تحقق';
      case UserRole.rep: return 'مندوب';
      case UserRole.storageActor: return 'مخزن';
      case UserRole.manager: return 'مدير';
      default: return '';
    }
  }
}
