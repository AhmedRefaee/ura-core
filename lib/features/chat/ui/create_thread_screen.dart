import 'package:flutter/material.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
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
    final result = await _repo.getUsers();
    if (!mounted) return;
    switch (result) {
      case AppSuccess(:final data):
        setState(() {
          _users = data;
          _loadingUsers = false;
        });
      case AppFailure(:final error):
        setState(() {
          _error = error.message;
          _loadingUsers = false;
        });
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
    if (_selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إضافة عضوين على الأقل للمجموعة')),
      );
      return;
    }
    setState(() => _creating = true);
    final threadResult = await _repo.createThread(title);
    switch (threadResult) {
      case AppFailure(:final error):
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message), backgroundColor: Colors.red),
          );
          setState(() => _creating = false);
        }
      case AppSuccess(:final data):
        await Future.wait(
          _selected.map((uid) => _repo.addParticipant(data, uid)),
        );
        if (mounted) Navigator.pop(context, (threadId: data, title: title));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.horizontalLarge,
              AppSpacing.verticalLarge,
              AppSpacing.horizontalLarge,
              AppSpacing.verticalSmall,
            ),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.horizontalLarge,
              AppSpacing.verticalSmall,
              AppSpacing.horizontalLarge,
              AppSpacing.verticalXSmall,
            ),
            child: Text(
              'إضافة أعضاء${_selected.isEmpty ? ' (2 على الأقل)' : ' (${_selected.length})'}',
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
    if (_loadingUsers) {
      return const AppLoadingState(message: 'جاري تحميل المستخدمين...');
    }
    if (_error != null) {
      return AppErrorView(
        title: 'تعذر تحميل المستخدمين',
        message: _error,
        retryText: 'إعادة المحاولة',
        onRetry: _loadUsers,
      );
    }
    if (_users.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline,
        title: 'لا يوجد مستخدمون',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.verticalLarge),
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final user = _users[i];
        final checked = _selected.contains(user.id);
        return CheckboxListTile(
          value: checked,
          onChanged: (_) => setState(() {
            if (checked) {
              _selected.remove(user.id);
            } else {
              _selected.add(user.id);
            }
          }),
          title: Text(user.fullName),
          subtitle: Text(_roleLabel(user.role)),
          secondary: CircleAvatar(
            child: Text(user.fullName.isNotEmpty ? user.fullName[0] : '?'),
          ),
          controlAffinity: ListTileControlAffinity.trailing,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.horizontalLarge,
            vertical: AppSpacing.verticalXSmall,
          ),
        );
      },
    );
  }

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.verifier:
        return 'موظف تحقق';
      case UserRole.rep:
        return 'مندوب';
      case UserRole.storageActor:
        return 'مخزن';
      case UserRole.manager:
        return 'مدير';
      default:
        return '';
    }
  }
}
