import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../manager/logic/user_orders_cubit.dart';
import '../../manager/ui/task_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Profile profile;
  final bool isSelf;

  const ProfileScreen({
    super.key,
    required this.profile,
    this.isSelf = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late String? _phone;

  @override
  void initState() {
    super.initState();
    _phone = widget.profile.phone;
  }

  Future<void> _editPhone() async {
    final controller = TextEditingController(text: _phone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditPhoneDialog(controller: controller),
    );
    if (result == null || !mounted) return;
    final repo = sl<AuthRepository>();
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final res = await repo.updatePhone(uid, result);
    if (!mounted) return;
    if (res is AppSuccess) {
      setState(() => _phone = result);
      context.read<AuthCubit>().refreshProfile();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل تحديث الرقم، يرجى المحاولة مجدداً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider(
      create: (_) => sl<UserOrdersCubit>()..loadForUser(widget.profile),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isSelf ? 'ملفي الشخصي' : widget.profile.fullName),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileHeader(profile: widget.profile, colorScheme: colorScheme),
              const SizedBox(height: 16),
              _InfoSection(
                profile: widget.profile,
                phone: _phone,
                theme: theme,
                onEditPhone: widget.isSelf ? _editPhone : null,
              ),
              const SizedBox(height: 16),
              _UserStatsSection(profile: widget.profile, theme: theme),
              const SizedBox(height: 16),
              _OrdersSection(theme: theme),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Profile profile;
  final ColorScheme colorScheme;

  const _ProfileHeader({required this.profile, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final avatarColor = _avatarColor(profile.role);
    final initials = _initials(profile.fullName);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: avatarColor,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              profile.fullName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Chip(
              label: Text(_roleLabel(profile.role)),
              backgroundColor: avatarColor.withValues(alpha: 0.12),
              labelStyle: TextStyle(
                color: avatarColor,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(color: avatarColor.withValues(alpha: 0.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final Profile profile;
  final String? phone;
  final ThemeData theme;
  final VoidCallback? onEditPhone;

  const _InfoSection({
    required this.profile,
    required this.phone,
    required this.theme,
    this.onEditPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'معلومات الحساب',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('رقم الواتساب'),
            subtitle: Text(
              phone ?? 'غير محدد',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: phone != null ? null : theme.disabledColor,
              ),
            ),
            trailing: onEditPhone != null
                ? IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEditPhone,
                    tooltip: 'تعديل الرقم',
                  )
                : null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('تاريخ الانضمام'),
            trailing: Text(
              _formatDate(profile.createdAt),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(
              profile.isApproved
                  ? Icons.verified_outlined
                  : Icons.pending_outlined,
              color: profile.isApproved ? Colors.green : Colors.orange,
            ),
            title: const Text('حالة الحساب'),
            trailing: Chip(
              label: Text(profile.isApproved ? 'موافق عليه' : 'قيد المراجعة'),
              backgroundColor: profile.isApproved
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.orange.withValues(alpha: 0.12),
              labelStyle: TextStyle(
                color: profile.isApproved ? Colors.green : Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide.none,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserStatsSection extends StatelessWidget {
  final Profile profile;
  final ThemeData theme;

  const _UserStatsSection({required this.profile, required this.theme});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserOrdersCubit, UserOrdersState>(
      builder: (context, state) {
        if (state is! UserOrdersLoaded) return const SizedBox.shrink();

        final allOrders = [...state.orders, ...state.doneOrders];
        if (allOrders.isEmpty) return const SizedBox.shrink();

        final doneStatuses = {OrderStatus.delivered, OrderStatus.deliveredToStorage};
        final delivered = allOrders.where((o) => doneStatuses.contains(o.status)).toList();

        double? avgPickup, avgTransit, avgTotal;

        if (profile.role == UserRole.rep) {
          final pickups = allOrders
              .where((o) => o.assignedAt != null && o.pickedUpAt != null)
              .map((o) => o.pickedUpAt!.difference(o.assignedAt!).inMinutes / 60.0)
              .toList();
          if (pickups.isNotEmpty) {
            avgPickup = pickups.reduce((a, b) => a + b) / pickups.length;
          }

          final transits = delivered
              .where((o) => o.pickedUpAt != null && o.deliveredAt != null)
              .map((o) => o.deliveredAt!.difference(o.pickedUpAt!).inMinutes / 60.0)
              .toList();
          if (transits.isNotEmpty) {
            avgTransit = transits.reduce((a, b) => a + b) / transits.length;
          }

          final totals = delivered
              .where((o) => o.createdAt != null && o.deliveredAt != null)
              .map((o) => o.deliveredAt!.difference(o.createdAt!).inMinutes / 60.0)
              .toList();
          if (totals.isNotEmpty) {
            avgTotal = totals.reduce((a, b) => a + b) / totals.length;
          }
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الإحصائيات',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatPill(
                      label: 'إجمالي',
                      value: '${allOrders.length}',
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      label: 'مكتمل',
                      value: '${delivered.length}',
                      color: Colors.green,
                    ),
                    if (avgTotal != null) ...[
                      const SizedBox(width: 8),
                      _StatPill(
                        label: 'متوسط الوقت',
                        value: '${avgTotal.toStringAsFixed(1)} س',
                        color: Colors.purple,
                      ),
                    ],
                  ],
                ),
                if (profile.role == UserRole.rep && (avgPickup != null || avgTransit != null)) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  if (avgPickup != null)
                    _StatRow(
                      label: 'متوسط وقت الاستلام من المخزن',
                      value: '${avgPickup.toStringAsFixed(1)} ساعة',
                      icon: Icons.access_time,
                      color: Colors.blue,
                    ),
                  if (avgTransit != null) ...[
                    const SizedBox(height: 8),
                    _StatRow(
                      label: 'متوسط وقت التوصيل للجهة',
                      value: '${avgTransit.toStringAsFixed(1)} ساعة',
                      icon: Icons.local_shipping,
                      color: Colors.orange,
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _OrdersSection extends StatelessWidget {
  final ThemeData theme;

  const _OrdersSection({required this.theme});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserOrdersCubit, UserOrdersState>(
      builder: (context, state) {
        if (state is UserOrdersLoading || state is UserOrdersInitial) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is UserOrdersError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(state.message,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
          );
        }
        if (state is UserOrdersLoaded) {
          final current = state.orders;
          final allDone = state.doneOrders;

          if (current.isEmpty && allDone.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لا توجد طلبات',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.disabledColor),
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (current.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'الطلبات الحالية',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...current.map(
                  (o) => OrderListTile(
                    order: o,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskDetailScreen(orderId: o.id),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (allDone.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'المكتملة (${allDone.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...allDone.map(
                  (o) => OrderListTile(
                    order: o,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskDetailScreen(orderId: o.id),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _EditPhoneDialog extends StatefulWidget {
  final TextEditingController controller;
  const _EditPhoneDialog({required this.controller});

  @override
  State<_EditPhoneDialog> createState() => _EditPhoneDialogState();
}

class _EditPhoneDialogState extends State<_EditPhoneDialog> {
  String? _error;

  void _submit() {
    final value = widget.controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'رقم الواتساب مطلوب ولا يمكن حذفه');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل رقم الواتساب'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'رقم الواتساب',
              hintText: '9665XXXXXXXX',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.phone),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

String _initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '؟';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

String _formatDate(DateTime? dt) {
  if (dt == null) return 'غير معروف';
  return '${dt.day}/${dt.month}/${dt.year}';
}

Color _avatarColor(UserRole? role) {
  switch (role) {
    case UserRole.manager:
      return Colors.deepPurple;
    case UserRole.verifier:
      return Colors.blue;
    case UserRole.rep:
      return Colors.green;
    case UserRole.storageActor:
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

String _roleLabel(UserRole? role) {
  switch (role) {
    case UserRole.manager:
      return 'مدير';
    case UserRole.verifier:
      return 'مشرف';
    case UserRole.rep:
      return 'مندوب';
    case UserRole.storageActor:
      return 'أمين المخزن';
    default:
      return 'غير محدد';
  }
}
