import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../data/manager_repository.dart';
import '../logic/manager_pending_users_cubit.dart';

class ManagerPendingUsersScreen extends StatefulWidget {
  const ManagerPendingUsersScreen({super.key});

  @override
  State<ManagerPendingUsersScreen> createState() =>
      _ManagerPendingUsersScreenState();
}

class _ManagerPendingUsersScreenState
    extends State<ManagerPendingUsersScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ManagerPendingUsersCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _OrgAccessCard(),
        Expanded(
          child: BlocBuilder<ManagerPendingUsersCubit, ManagerPendingUsersState>(
            builder: (context, state) {
              if (state is ManagerPendingUsersLoading ||
                  state is ManagerPendingUsersInitial) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ManagerPendingUsersError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(state.message,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            context.read<ManagerPendingUsersCubit>().load(),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }
              if (state is ManagerPendingUsersLoaded) {
                if (state.users.isEmpty) {
                  return const Center(
                    child: Text('لا يوجد مستخدمون بانتظار الموافقة'),
                  );
                }
                return ListView.builder(
                  itemCount: state.users.length,
                  itemBuilder: (context, index) {
                    final user = state.users[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(user.fullName[0])),
                        title: Text(user.fullName),
                        subtitle: Text(user.phone ?? 'لا يوجد رقم هاتف'),
                        trailing: FilledButton(
                          onPressed: () => _showApproveDialog(
                              context, user.id, user.fullName),
                          child: const Text('تفعيل'),
                        ),
                      ),
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  void _showApproveDialog(
      BuildContext context, String userId, String fullName) {
    String selectedRole = 'rep';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('تفعيل: $fullName'),
          content: RadioGroup<String>(
            groupValue: selectedRole,
            onChanged: (v) => setDialogState(() => selectedRole = v!),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text('مندوب'),
                  value: 'rep',
                ),
                RadioListTile<String>(
                  title: Text('أمين مخزن'),
                  value: 'storage_actor',
                ),
                RadioListTile<String>(
                  title: Text('مشرف'),
                  value: 'verifier',
                ),
                RadioListTile<String>(
                  title: Text('مدير'),
                  value: 'manager',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context
                    .read<ManagerPendingUsersCubit>()
                    .approveUser(userId, selectedRole);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header card on the pending-users tab: shows the org join code (copyable)
/// and lets the manager rotate it.
class _OrgAccessCard extends StatefulWidget {
  const _OrgAccessCard();

  @override
  State<_OrgAccessCard> createState() => _OrgAccessCardState();
}

class _OrgAccessCardState extends State<_OrgAccessCard> {
  final _repo = sl<ManagerRepository>();
  String? _joinCode;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.fetchOrgAccess();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is AppSuccess<({String name, String joinCode})>) {
        _joinCode = result.data.joinCode;
      }
    });
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final result = await _repo.rotateJoinCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is AppSuccess<String>) _joinCode = result.data;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('وصول الفريق',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('رمز الانضمام: ${_joinCode ?? '—'}')),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'نسخ',
                  onPressed: _joinCode == null
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: _joinCode!)),
                ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('تدوير الرمز'),
              onPressed: _busy ? null : _rotate,
            ),
          ],
        ),
      ),
    );
  }
}
