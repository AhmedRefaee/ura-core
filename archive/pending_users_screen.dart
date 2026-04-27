import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../lib/features/verifier/logic/pending_users_cubit.dart';

class PendingUsersScreen extends StatefulWidget {
  const PendingUsersScreen({super.key});

  @override
  State<PendingUsersScreen> createState() => _PendingUsersScreenState();
}

class _PendingUsersScreenState extends State<PendingUsersScreen> {
  @override
  void initState() {
    super.initState();
    context.read<PendingUsersCubit>().loadPendingUsers();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PendingUsersCubit, PendingUsersState>(
      builder: (context, state) {
        if (state is PendingUsersLoading || state is PendingUsersInitial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PendingUsersError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.read<PendingUsersCubit>().loadPendingUsers(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is PendingUsersLoaded) {
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
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(child: Text(user.fullName[0])),
                  title: Text(user.fullName),
                  subtitle: Text(user.phone ?? 'لا يوجد رقم هاتف'),
                  trailing: FilledButton(
                    onPressed: () => _showApproveDialog(context, user.id, user.fullName),
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

  void _showApproveDialog(BuildContext context, String userId, String fullName) {
    String selectedRole = 'rep';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('تفعيل: $fullName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختر الدور:'),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('مندوب'),
                value: 'rep',
                groupValue: selectedRole,
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              ),
              RadioListTile<String>(
                title: const Text('أمين مخزن'),
                value: 'storage_actor',
                groupValue: selectedRole,
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              ),
              RadioListTile<String>(
                title: const Text('مشرف'),
                value: 'verifier',
                groupValue: selectedRole,
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<PendingUsersCubit>().approveUser(userId, selectedRole);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }
}
