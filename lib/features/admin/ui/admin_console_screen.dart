import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../../core/design_system/theme/theme.dart';
import '../data/admin_repository.dart';
import '../logic/admin_cubit.dart';

const _roles = ['rep', 'storage_actor', 'verifier', 'manager'];

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

  Future<void> _approve(AdminMember m) async {
    final role = await showDialog<String>(
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
    if (role == null) return;
    await widget.cubit.approveUser(m.id, role);
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
                    ? null
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
