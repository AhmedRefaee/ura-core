import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../features/auth/logic/auth_cubit.dart';
import '../../../features/auth/logic/auth_state.dart';
import '../../../shared/models/profile.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../data/chat_repository.dart';

class ThreadMembersScreen extends StatefulWidget {
  final String threadId;
  final String threadTitle;
  final String createdBy;

  const ThreadMembersScreen({
    super.key,
    required this.threadId,
    required this.threadTitle,
    required this.createdBy,
  });

  @override
  State<ThreadMembersScreen> createState() => _ThreadMembersScreenState();
}

class _ThreadMembersScreenState extends State<ThreadMembersScreen> {
  final _repo = sl<ChatRepository>();
  List<Profile> _members = [];
  bool _loading = true;
  String? _error;
  bool _systemMessagesEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadSystemMessagesSetting();
  }

  Future<void> _loadMembers() async {
    setState(() { _loading = true; _error = null; });
    try {
      final membersResult = await _repo.getThreadParticipants(widget.threadId);
      if (membersResult is AppSuccess<List<Profile>>) {
        if (mounted) setState(() { _members = membersResult.data; _loading = false; });
      } else if (mounted) {
        final error = (membersResult as AppFailure).error;
        setState(() { _error = error.message; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadSystemMessagesSetting() async {
    try {
      final result = await _repo.getThread(widget.threadId);
      if (result is AppSuccess<Map<String, dynamic>>) {
        final threadData = result.data;
        if (mounted) {
          setState(() {
            _systemMessagesEnabled =
                (threadData['system_messages_enabled'] as bool?) ?? true;
          });
        }
      }
    } catch (e) {
      // Best effort; default to true
    }
  }

  Future<void> _toggleSystemMessages(bool value) async {
    try {
      await _repo.toggleSystemMessages(widget.threadId, value);
      if (mounted) setState(() => _systemMessagesEnabled = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _canManage(BuildContext context) {
    final state = context.read<AuthCubit>().state;
    if (state is! AuthAuthenticated) return false;
    final role = state.profile.role;
    return role == UserRole.verifier || role == UserRole.manager;
  }

  Future<void> _removeMember(Profile member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إزالة عضو'),
        content: Text('هل تريد إزالة ${member.fullName} من المجموعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.removeParticipant(widget.threadId, member.id);
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addMembers() async {
    final currentIds = _members.map((m) => m.id).toSet();
    List<Profile> allUsers;
    try {
      final usersResult = await _repo.getUsers();
      if (usersResult is AppSuccess<List<Profile>>) {
        allUsers = usersResult.data;
      } else {
        final error = (usersResult as AppFailure).error;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: ${error.message}'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final available = allUsers.where((u) => !currentIds.contains(u.id)).toList();
    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد مستخدمون آخرون للإضافة')),
      );
      return;
    }

    final toAdd = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddMembersSheet(users: available),
    );
    if (toAdd == null || toAdd.isEmpty) return;
    try {
      await Future.wait(toAdd.map((uid) => _repo.addParticipant(widget.threadId, uid)));
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _canManage(context);
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = myId != null && myId == widget.createdBy;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('أعضاء: ${widget.threadTitle}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMembers,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(canManage)),
          // System messages toggle (only for thread creator)
          if (isCreator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SwitchListTile(
                title: const Text('رسائل النظام التلقائية'),
                subtitle: const Text(
                  'إظهار إشعارات تغيير حالة الطلب في المحادثة',
                  style: TextStyle(fontSize: 12),
                ),
                value: _systemMessagesEnabled,
                onChanged: _toggleSystemMessages,
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _addMembers,
              icon: const Icon(Icons.person_add),
              label: const Text('إضافة عضو'),
            )
          : null,
    );
  }

  Widget _buildBody(bool canManage) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadMembers, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_members.isEmpty) {
      return const Center(child: Text('لا يوجد أعضاء', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: _members.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, i) {
        final member = _members[i];
        final isCreator = member.id == widget.createdBy;
        return ListTile(
          leading: CircleAvatar(
            child: Text(member.fullName.isNotEmpty ? member.fullName[0] : '?'),
          ),
          title: Text(member.fullName),
          subtitle: Text(_roleLabel(member.role)),
          trailing: isCreator
              ? const Chip(label: Text('منشئ'), visualDensity: VisualDensity.compact)
              : canManage
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      tooltip: 'إزالة',
                      onPressed: () => _removeMember(member),
                    )
                  : null,
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

class _AddMembersSheet extends StatefulWidget {
  final List<Profile> users;
  const _AddMembersSheet({required this.users});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'اختر أعضاء للإضافة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text('إضافة (${_selected.length})'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: widget.users.length,
              itemBuilder: (_, i) {
                final user = widget.users[i];
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
            ),
          ),
        ],
      ),
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
