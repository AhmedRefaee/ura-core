import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
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

  const ProfileScreen({super.key, required this.profile, this.isSelf = true});

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
    return BlocProvider(
      create: (_) => sl<UserOrdersCubit>()..loadForUser(widget.profile),
      child: CollapsingHeaderWrapper(
        title: Text(widget.isSelf ? 'ملفي الشخصي' : widget.profile.fullName),
        body: BlocBuilder<UserOrdersCubit, UserOrdersState>(
          builder: (context, state) => Builder(
            builder: (ctx) {
              if (state is UserOrdersLoading || state is UserOrdersInitial) {
                return const CollapsingInnerScrollBody(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: AppLoadingIndicator()),
                    ),
                  ],
                );
              }
              if (state is UserOrdersError) {
                return CollapsingInnerScrollBody(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          state.message,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                );
              }
              final active = state is UserOrdersLoaded
                  ? state.orders
                  : <Order>[];
              final done = state is UserOrdersLoaded
                  ? state.doneOrders
                  : <Order>[];
              return _ProfileBody(
                profile: widget.profile,
                phone: _phone,
                onEditPhone: widget.isSelf ? _editPhone : null,
                active: active,
                done: done,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Profile body (owns pagination state) ──────────────────────────────────────

class _ProfileBody extends StatefulWidget {
  final Profile profile;
  final String? phone;
  final VoidCallback? onEditPhone;
  final List<Order> active;
  final List<Order> done;

  const _ProfileBody({
    required this.profile,
    required this.phone,
    required this.onEditPhone,
    required this.active,
    required this.done,
  });

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  static const _pageSize = 20;
  int _doneLimit = _pageSize;

  @override
  void didUpdateWidget(_ProfileBody old) {
    super.didUpdateWidget(old);
    if (old.done != widget.done) _doneLimit = _pageSize;
  }

  @override
  Widget build(BuildContext context) {
    const doneStatuses = {
      OrderStatus.delivered,
      OrderStatus.deliveredToStorage,
    };
    final allOrders = [...widget.active, ...widget.done];
    final delivered = allOrders
        .where((o) => doneStatuses.contains(o.status))
        .toList();

    double? avgPickup, avgTransit, avgTotal;
    if (widget.profile.role == UserRole.rep) {
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

    final visibleDone = widget.done.take(_doneLimit).toList();
    final hasMore = widget.done.length > _doneLimit;

    return Builder(
      builder: (ctx) => CollapsingInnerScrollBody(
        slivers: [
          // ── Fixed info sections ──────────────────────────────────────────
          SliverPadding(
            padding: AppSpacing.allMedium,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _ProfileHeader(profile: widget.profile),
                SizedBox(height: AppSpacing.verticalMedium),
                _InfoSection(
                  profile: widget.profile,
                  phone: widget.phone,
                  onEditPhone: widget.onEditPhone,
                ),
                if (allOrders.isNotEmpty) ...[
                  SizedBox(height: AppSpacing.verticalMedium),
                  _StatsCard(
                    profile: widget.profile,
                    allOrders: allOrders,
                    delivered: delivered,
                    avgPickup: avgPickup,
                    avgTransit: avgTransit,
                    avgTotal: avgTotal,
                  ),
                ],
              ]),
            ),
          ),

          // ── Active orders ────────────────────────────────────────────────
          if (widget.active.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.horizontalMedium,
                AppSpacing.verticalSmall,
                AppSpacing.horizontalMedium,
                AppSpacing.verticalXSmall,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'الطلبات الحالية',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.horizontalMedium,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => OrderListTile(
                    order: widget.active[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TaskDetailScreen(orderId: widget.active[i].id),
                      ),
                    ),
                  ),
                  childCount: widget.active.length,
                ),
              ),
            ),
          ],

          // ── Done orders (paginated) ──────────────────────────────────────
          if (widget.done.isNotEmpty) ...[
          
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.horizontalMedium,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => OrderListTile(
                    order: visibleDone[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TaskDetailScreen(orderId: visibleDone[i].id),
                      ),
                    ),
                  ),
                  childCount: visibleDone.length,
                ),
              ),
            ),
            if (hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.horizontalMedium,
                    vertical: AppSpacing.verticalSmall,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _doneLimit += _pageSize),
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      'عرض المزيد — ${widget.done.length - _doneLimit} متبقية',
                    ),
                  ),
                ),
              ),
          ],

          // ── No orders at all ─────────────────────────────────────────────
          if (widget.active.isEmpty && widget.done.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(top: AppSpacing.verticalXLarge),
                  child: Text(
                    'لا توجد طلبات',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.verticalXXLarge),
          ),
        ],
      ),
    );
  }
}

// ── Profile header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final Profile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final avatarColor = _avatarColor(profile.role);
    final initials = _initials(profile.fullName);

    return Card(
      child: Padding(
        padding: AppSpacing.symmetric(
          horizontal: AppSpacing.horizontalMedium,
          vertical: AppSpacing.verticalXLarge,
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: avatarColor,
              child: Text(
                initials,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.verticalSmall),
            Text(
              profile.fullName,
              style: AppTextStyles.headlineSmall.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.verticalXSmall),
            Chip(
              label: Text(_roleLabel(profile.role)),
              backgroundColor: avatarColor.withValues(alpha: 0.12),
              labelStyle: AppTextStyles.labelMedium.copyWith(
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

// ── Info section ──────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final Profile profile;
  final String? phone;
  final VoidCallback? onEditPhone;

  const _InfoSection({
    required this.profile,
    required this.phone,
    this.onEditPhone,
  });

  @override
  Widget build(BuildContext context) {
    final approvedColor = SemanticColors.success;
    final pendingColor = SemanticColors.warning;
    final statusColor = profile.isApproved ? approvedColor : pendingColor;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppSpacing.symmetric(
              horizontal: AppSpacing.horizontalMedium,
              vertical: AppSpacing.verticalMedium,
            ),
            child: Text(
              'معلومات الحساب',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('رقم الواتساب'),
            subtitle: Text(
              phone ?? 'غير محدد',
              style: AppTextStyles.bodyMedium.copyWith(
                color: phone != null ? null : AppColors.textTertiary,
              ),
            ),
            trailing: onEditPhone != null
                ? AppIconButton(
                    icon: Icons.edit_outlined,
                    variant: AppIconButtonVariant.text,
                    onPressed: onEditPhone!,
                    tooltip: 'تعديل الرقم',
                  )
                : null,
            showDivider: true,
          ),
          AppListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('تاريخ الانضمام'),
            trailing: Text(
              _formatDate(profile.createdAt),
              style: AppTextStyles.bodyMedium,
            ),
            showDivider: true,
          ),
          AppListTile(
            leading: Icon(
              profile.isApproved
                  ? Icons.verified_outlined
                  : Icons.pending_outlined,
              color: statusColor,
            ),
            title: const Text('حالة الحساب'),
            trailing: Chip(
              label: Text(profile.isApproved ? 'موافق عليه' : 'قيد المراجعة'),
              backgroundColor: statusColor.withValues(alpha: 0.12),
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: statusColor,
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

// ── Stats card (data passed in — no BlocBuilder needed) ───────────────────────

class _StatsCard extends StatelessWidget {
  final Profile profile;
  final List<Order> allOrders;
  final List<Order> delivered;
  final double? avgPickup;
  final double? avgTransit;
  final double? avgTotal;

  const _StatsCard({
    required this.profile,
    required this.allOrders,
    required this.delivered,
    this.avgPickup,
    this.avgTransit,
    this.avgTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإحصائيات',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: AppSpacing.verticalSmall),
            // Wrap prevents overflow on small screens
            Wrap(
              spacing: AppSpacing.horizontalXSmall,
              runSpacing: AppSpacing.verticalXSmall,
              children: [
                _StatPill(
                  label: 'إجمالي',
                  value: '${allOrders.length}',
                  color: Colors.blue,
                ),
                _StatPill(
                  label: 'مكتمل',
                  value: '${delivered.length}',
                  color: SemanticColors.success,
                ),
                if (avgTotal != null)
                  _StatPill(
                    label: 'متوسط الوقت',
                    value: '${avgTotal!.toStringAsFixed(1)} س',
                    color: Colors.purple,
                  ),
              ],
            ),
            if (profile.role == UserRole.rep &&
                (avgPickup != null || avgTransit != null)) ...[
              SizedBox(height: AppSpacing.verticalMedium),
              const Divider(height: 1),
              SizedBox(height: AppSpacing.verticalSmall),
              if (avgPickup != null)
                _StatRow(
                  label: 'متوسط وقت الاستلام من المخزن',
                  value: '${avgPickup!.toStringAsFixed(1)} ساعة',
                  icon: Icons.access_time,
                  color: Colors.blue,
                ),
              if (avgTransit != null) ...[
                SizedBox(height: AppSpacing.verticalXSmall),
                _StatRow(
                  label: 'متوسط وقت التوصيل للجهة',
                  value: '${avgTransit!.toStringAsFixed(1)} ساعة',
                  icon: Icons.local_shipping,
                  color: SemanticColors.warning,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.symmetric(
        horizontal: AppSpacing.horizontalSmall,
        vertical: AppSpacing.verticalXSmall,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: AppSpacing.verticalXSmall / 2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
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
        SizedBox(width: AppSpacing.horizontalXSmall),
        Expanded(child: Text(label, style: AppTextStyles.bodySmall)),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Edit phone dialog ─────────────────────────────────────────────────────────

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
    if (!RegExp(r'^05\d{8}$').hasMatch(value)) {
      setState(() => _error = 'الرقم يجب أن يبدأ بـ 05 ويتكون من 10 أرقام');
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
              hintText: '05XXXXXXXX',
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
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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
  return switch (role) {
    UserRole.manager => Colors.deepPurple,
    UserRole.verifier => Colors.blue,
    UserRole.rep => SemanticColors.success,
    UserRole.storageActor => SemanticColors.warning,
    _ => AppColors.textTertiary,
  };
}

String _roleLabel(UserRole? role) {
  return switch (role) {
    UserRole.manager => 'مدير',
    UserRole.verifier => 'مشرف',
    UserRole.rep => 'مندوب',
    UserRole.storageActor => 'أمين المخزن',
    _ => 'غير محدد',
  };
}
