import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    return BlocBuilder<ManagerPendingUsersCubit, ManagerPendingUsersState>(
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
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(child: Text(user.fullName[0])),
                  title: Text(user.fullName),
                  subtitle: Text(user.phone ?? 'لا يوجد رقم هاتف'),
                  trailing: FilledButton(
                    onPressed: () =>
                        _showApproveDialog(context, user.id, user.fullName),
                    child: const Text('تفعيل'),
                  ),
                ),
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
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
