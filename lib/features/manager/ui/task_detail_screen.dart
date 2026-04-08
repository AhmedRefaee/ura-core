import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/models/profile.dart';
import '../logic/task_detail_cubit.dart';

class TaskDetailScreen extends StatelessWidget {
  final String orderId;
  const TaskDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl.get<TaskDetailCubit>(param1: orderId)..load(),
      child: const _TaskDetailView(),
    );
  }
}

class _TaskDetailView extends StatelessWidget {
  const _TaskDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TaskDetailCubit, TaskDetailState>(
      builder: (context, state) {
        if (state is TaskDetailLoading || state is TaskDetailInitial) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state is TaskDetailError) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل المهمة')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.read<TaskDetailCubit>().load(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        if (state is! TaskDetailLoaded) return const SizedBox.shrink();

        final order = state.order;
        final auditLog = state.auditLog;

        return Scaffold(
          appBar: AppBar(
            title: Text(order.entity?.name ?? 'تفاصيل المهمة'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<TaskDetailCubit>().load(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OrderInfoCard(order: order),
              const SizedBox(height: 16),
              _StatusTimeline(order: order, auditLog: auditLog),
              const SizedBox(height: 16),
              _ItemsCard(items: order.items),
            ],
          ),
        );
      },
    );
  }
}

// ── Order Info ────────────────────────────────────────────────────────────────

class _OrderInfoCard extends StatelessWidget {
  final Order order;
  const _OrderInfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(Icons.business, 'الجهة', order.entity?.name ?? '—'),
            _Row(Icons.swap_horiz, 'الاتجاه', order.directionLabel),
            _Row(Icons.person_outline, 'المندوب', order.rep?.fullName ?? 'لا يوجد'),
            if (order.notes != null && order.notes!.isNotEmpty)
              _Row(Icons.notes, 'ملاحظات', order.notes!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Status Timeline ───────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final Order order;
  final List<AuditLogEntry> auditLog;
  const _StatusTimeline({required this.order, required this.auditLog});

  AuditLogEntry? _entryFor(OrderStatus status) {
    try {
      return auditLog.firstWhere((e) => e.newStatus == status);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(
        label: 'تم الإنشاء',
        icon: Icons.assignment_outlined,
        color: Colors.orange,
        timestamp: order.assignedAt,
        performer: order.creator,
        reached: true,
      ),
      _TimelineStep(
        label: 'تم الاستلام',
        icon: Icons.inventory_2_outlined,
        color: Colors.blue,
        timestamp: order.pickedUpAt,
        performer: _entryFor(OrderStatus.pickedUp)?.performer,
        reached: order.status != OrderStatus.assigned,
      ),
      _TimelineStep(
        label: 'في الطريق',
        icon: Icons.local_shipping_outlined,
        color: Colors.purple,
        timestamp: order.moveStartedAt,
        performer: _entryFor(OrderStatus.onTheMove)?.performer,
        reached: order.status == OrderStatus.onTheMove ||
            order.status == OrderStatus.delivered,
      ),
      _TimelineStep(
        label: 'تم التسليم',
        icon: Icons.check_circle_outline,
        color: Colors.green,
        timestamp: order.deliveredAt,
        performer: _entryFor(OrderStatus.delivered)?.performer,
        reached: order.status == OrderStatus.delivered,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مسار الحالة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            ...steps.map((s) => _StepTile(step: s)),
          ],
        ),
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;
  final Color color;
  final DateTime? timestamp;
  final Profile? performer;
  final bool reached;

  const _TimelineStep({
    required this.label,
    required this.icon,
    required this.color,
    required this.timestamp,
    required this.performer,
    required this.reached,
  });
}

class _StepTile extends StatelessWidget {
  final _TimelineStep step;
  const _StepTile({required this.step});

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year}  $h:$m';
  }

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.rep:
        return 'مندوب';
      case UserRole.storageActor:
        return 'أمين مخزن';
      case UserRole.verifier:
        return 'مشرف';
      case UserRole.manager:
        return 'مدير';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = step.reached;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    active ? step.color : Colors.grey.shade300,
                child: Icon(step.icon,
                    size: 16,
                    color: active ? Colors.white : Colors.grey),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: active ? null : Colors.grey,
                    )),
                if (active) ...[
                  const SizedBox(height: 2),
                  Text(
                    _fmt(step.timestamp),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (step.performer != null)
                    Text(
                      '${step.performer!.fullName}  ·  ${_roleLabel(step.performer!.role)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ] else
                  Text('لم يتم بعد',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Items Card ────────────────────────────────────────────────────────────────

class _ItemsCard extends StatelessWidget {
  final List<OrderItem> items;
  const _ItemsCard({required this.items});

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year}  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الأصناف',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...items.map((item) => _ItemRow(item: item, fmt: _fmt)),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final OrderItem item;
  final String Function(DateTime?) fmt;
  const _ItemRow({required this.item, required this.fmt});

  @override
  Widget build(BuildContext context) {
    Color checkColor;
    IconData checkIcon;
    String checkLabel;
    switch (item.checkStatus) {
      case ItemCheckStatus.checked:
        checkColor = Colors.green;
        checkIcon = Icons.check_circle;
        checkLabel = 'تم الفحص';
      case ItemCheckStatus.rejected:
        checkColor = Colors.red;
        checkIcon = Icons.cancel;
        checkLabel = 'مرفوض';
      case ItemCheckStatus.pending:
        checkColor = Colors.grey;
        checkIcon = Icons.radio_button_unchecked;
        checkLabel = 'قيد الانتظار';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isCustom ? Icons.shopping_bag_outlined : Icons.inventory_outlined,
            size: 18,
            color: item.isCustom ? Colors.orange : Colors.teal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('الكمية: ${item.quantity}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (!item.isCustom) ...[
                  Row(
                    children: [
                      Icon(checkIcon, size: 14, color: checkColor),
                      const SizedBox(width: 4),
                      Text(checkLabel,
                          style: TextStyle(fontSize: 12, color: checkColor)),
                      if (item.checker != null) ...[
                        const Text('  ·  ',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(item.checker!.fullName,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ],
                  ),
                  if (item.checkedAt != null)
                    Text(fmt(item.checkedAt),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
