import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../../core/design_system/theme/theme.dart';
import '../data/admin_repository.dart';
import '../logic/admin_cubit.dart';

const _roles = ['rep', 'storage_actor', 'verifier', 'manager', 'admin'];

/// Hidden platform-admin console: cross-org overview and controls. Reachable
/// only by accounts carrying the platform_admin JWT claim.
class AdminConsoleScreen extends StatelessWidget {
  const AdminConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminCubit(sl<AdminRepository>())..load(),
      child: const _AdminConsoleView(),
    );
  }
}

class _AdminConsoleView extends StatelessWidget {
  const _AdminConsoleView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة المشرف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AdminCubit>().load(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthCubit>().signOut(),
          ),
        ],
      ),
      body: BlocBuilder<AdminCubit, AdminState>(
        builder: (context, state) {
          if (state.loading && state.orgs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.orgs.isEmpty) {
            return Center(child: Text(state.error!));
          }
          if (state.orgs.isEmpty) {
            return const Center(child: Text('لا توجد مؤسسات'));
          }
          return ListView.separated(
            padding: AppSpacing.screenPaddingInsets,
            itemCount: state.orgs.length,
            separatorBuilder: (_, _) =>
                SizedBox(height: AppSpacing.verticalMedium),
            itemBuilder: (_, i) => _OrgCard(org: state.orgs[i]),
          );
        },
      ),
    );
  }
}

class _OrgCard extends StatelessWidget {
  final AdminOrg org;
  const _OrgCard({required this.org});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.verticalMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(org.name, style: AppTextStyles.titleMedium),
            SizedBox(height: AppSpacing.verticalSmall),
            Text(
              'الأعضاء: ${org.memberCount} • بانتظار الموافقة: ${org.pendingCount}',
              style: AppTextStyles.bodySmall,
            ),
            Row(
              children: [
                Expanded(
                  child: Text('رمز الانضمام: ${org.joinCode}',
                      style: AppTextStyles.bodySmall),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'نسخ',
                  onPressed: () => Clipboard.setData(
                      ClipboardData(text: org.joinCode)),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('ظاهرة في الدليل',
                        style: AppTextStyles.bodySmall),
                    value: org.isDiscoverable,
                    onChanged: (v) => cubit.toggleDiscoverable(org.id, v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تدوير الرمز'),
                  onPressed: () => cubit.rotateJoinCode(org.id),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.people, size: 18),
                  label: const Text('الأعضاء'),
                  onPressed: () => _showMembers(context, cubit, org),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  icon: Icon(Icons.delete_forever,
                      size: 18, color: AppColors.error),
                  label: Text('حذف المؤسسة',
                      style: TextStyle(color: AppColors.error)),
                  onPressed: () => _confirmDeleteOrg(context, cubit, org),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMembers(BuildContext context, AdminCubit cubit, AdminOrg org) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MembersSheet(cubit: cubit, org: org),
    );
  }

  Future<void> _confirmDeleteOrg(
      BuildContext context, AdminCubit cubit, AdminOrg org) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteOrgDialog(org: org),
    );
    if (confirmed != true) return;
    final result = await cubit.deleteOrganization(org.id);
    if (result is AppFailure<void> && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message)),
      );
    }
  }
}

class _DeleteOrgDialog extends StatefulWidget {
  final AdminOrg org;
  const _DeleteOrgDialog({required this.org});

  @override
  State<_DeleteOrgDialog> createState() => _DeleteOrgDialogState();
}

class _DeleteOrgDialogState extends State<_DeleteOrgDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حذف المؤسسة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'هذا الإجراء لا يمكن التراجع عنه. للتأكيد، اكتب اسم المؤسسة بالضبط:\n"${widget.org.name}"',
          ),
          SizedBox(height: AppSpacing.verticalMedium),
          TextField(
            controller: _controller,
            onChanged: (v) =>
                setState(() => _matches = v.trim() == widget.org.name),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text('حذف', style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }
}

class _MembersSheet extends StatefulWidget {
  final AdminCubit cubit;
  final AdminOrg org;
  const _MembersSheet({required this.cubit, required this.org});

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  late Future<AppResult<List<AdminMember>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.cubit.members(widget.org.id);
  }

  void _reload() =>
      setState(() => _future = widget.cubit.members(widget.org.id));

  Future<String?> _pickRole() {
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('تعيين الدور'),
        children: _roles
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r),
                  child: Text(r),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _approve(AdminMember m) async {
    final role = await _pickRole();
    if (role == null) return;
    await widget.cubit.approveUser(m.id, role);
    if (mounted) _reload();
  }

  Future<void> _changeRole(AdminMember m) async {
    final role = await _pickRole();
    if (role == null) return;
    final result = await widget.cubit.changeMemberRole(m.id, role);
    if (result is AppFailure<void> && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message)),
      );
    }
    if (mounted) _reload();
  }

  Future<void> _remove(AdminMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إزالة العضو'),
        content: Text(
          'هل تريد إزالة "${m.fullName}"؟ سيحتاج إلى موافقة جديدة للوصول مرة أخرى.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('إزالة', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await widget.cubit.removeMember(m.id);
    if (result is AppFailure<void> && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message)),
      );
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scrollController) => FutureBuilder<AppResult<List<AdminMember>>>(
        future: _future,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snap.data!;
          if (result is! AppSuccess<List<AdminMember>>) {
            return const Center(child: Text('تعذّر تحميل الأعضاء'));
          }
          final members = result.data;
          return ListView.builder(
            controller: scrollController,
            itemCount: members.length,
            itemBuilder: (_, i) {
              final m = members[i];
              return ListTile(
                title: Text(m.fullName),
                subtitle: Text(m.isApproved
                    ? (m.role ?? '—')
                    : 'بانتظار الموافقة'),
                trailing: m.isApproved
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            tooltip: 'تغيير الدور',
                            onPressed: () => _changeRole(m),
                          ),
                          IconButton(
                            icon: Icon(Icons.person_remove,
                                size: 20, color: AppColors.error),
                            tooltip: 'إزالة',
                            onPressed: () => _remove(m),
                          ),
                        ],
                      )
                    : TextButton(
                        onPressed: () => _approve(m),
                        child: const Text('موافقة'),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
