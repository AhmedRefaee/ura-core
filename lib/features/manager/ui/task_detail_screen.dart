import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_edit_log_entry.dart';
import '../../../shared/models/order_item.dart';
import '../../inventory/ui/inventory_item_detail_screen.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/order_status_theme.dart';
import '../../../shared/widgets/receipt_viewer_screen.dart';
import '../../../features/chat/data/chat_repository.dart';
import '../../../features/chat/ui/chat_thread_screen.dart';
import '../../../features/verifier/data/order_repository.dart';
import '../../../features/verifier/logic/edit_order_cubit.dart';
import '../../../features/verifier/ui/edit_order_screen.dart';
import '../logic/task_detail_cubit.dart';
import '../../profile/ui/profile_screen.dart';

class TaskDetailScreen extends StatelessWidget {
  final String orderId;
  final bool showDeleteButton;
  const TaskDetailScreen({super.key, required this.orderId, this.showDeleteButton = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl.get<TaskDetailCubit>(param1: orderId)..load(),
      child: _TaskDetailView(showDeleteButton: showDeleteButton),
    );
  }
}

class _TaskDetailView extends StatelessWidget {
  final bool showDeleteButton;
  const _TaskDetailView({this.showDeleteButton = false});

  void _openEditOrder(BuildContext context, String orderId) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl.get<EditOrderCubit>(param1: orderId)..loadOrder(),
          child: const EditOrderScreen(),
        ),
      ),
    );
    if (result == true && context.mounted) {
      context.read<TaskDetailCubit>().load();
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('حذف الطلب'),
            content: const Text('هل أنت متأكد من حذف هذا الطلب؟ لا يمكن التراجع عن هذا الإجراء.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TaskDetailCubit, TaskDetailState>(
      listener: (context, state) {
        if (state is TaskDetailDeleted) Navigator.of(context).pop(true);
      },
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
        final receipts = state.receipts;
        final canDelete = showDeleteButton && order.status != OrderStatus.delivered;

        return Scaffold(
          appBar: AppBar(
            title: Text(order.entity?.name ?? 'تفاصيل المهمة'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'تعديل الطلب',
                onPressed: () => _openEditOrder(context, order.id),
              ),
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'حذف الطلب',
                  onPressed: () async {
                    final confirmed = await _confirmDelete(context);
                    if (confirmed && context.mounted) {
                      context.read<TaskDetailCubit>().deleteOrder();
                    }
                  },
                ),
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
              _CommunicationHistorySection(orderId: order.id),
              const SizedBox(height: 16),
              _StatusTimeline(order: order, auditLog: auditLog),
              const SizedBox(height: 16),
              _ItemsCard(items: order.items, orderStatus: order.status, receipts: receipts, stockItems: state.stockItems, orderDirection: order.direction),
              const SizedBox(height: 16),
              _EditHistorySection(orderId: order.id),
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
            _Row(
              Icons.person_outline,
              'المندوب',
              order.rep?.fullName ?? 'لا يوجد',
              onTap: order.rep != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            profile: order.rep!,
                            isSelf: false,
                          ),
                        ),
                      )
                  : null,
            ),
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
  final VoidCallback? onTap;
  const _Row(this.icon, this.label, this.value, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final valueWidget = onTap != null
        ? GestureDetector(
            onTap: onTap,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          )
        : Text(value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(child: valueWidget),
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
    final pickedUpEntry = _entryFor(OrderStatus.pickedUp);
    final onTheMoveEntry = _entryFor(OrderStatus.onTheMove);
    final deliveredEntry = _entryFor(OrderStatus.delivered);

    final steps = [
      _TimelineStep(
        label: 'تم الإنشاء',
        icon: OrderStatus.assigned.icon,
        color: OrderStatus.assigned.color,
        timestamp: order.assignedAt,
        performer: order.creator,
        reached: true,
      ),
      _TimelineStep(
        label: 'تم الاستلام',
        icon: OrderStatus.pickedUp.icon,
        color: OrderStatus.pickedUp.color,
        timestamp: order.pickedUpAt,
        performer: pickedUpEntry?.performer,
        notes: pickedUpEntry?.notes,
        reached: order.status != OrderStatus.assigned,
      ),
      _TimelineStep(
        label: 'في الطريق',
        icon: OrderStatus.onTheMove.icon,
        color: OrderStatus.onTheMove.color,
        timestamp: order.moveStartedAt ?? onTheMoveEntry?.serverTimestamp,
        performer: onTheMoveEntry?.performer,
        notes: onTheMoveEntry?.notes,
        reached: order.status == OrderStatus.onTheMove ||
            order.status == OrderStatus.delivered,
      ),
      _TimelineStep(
        label: 'تم التسليم',
        icon: OrderStatus.delivered.icon,
        color: OrderStatus.delivered.color,
        timestamp: order.deliveredAt ?? deliveredEntry?.serverTimestamp,
        performer: deliveredEntry?.performer,
        notes: deliveredEntry?.notes,
        reached: order.status == OrderStatus.delivered,
      ),
    ];

    final List<Widget> tiles = [];
    for (int i = 0; i < steps.length; i++) {
      tiles.add(_StepTile(step: steps[i]));
      if (i < steps.length - 1) {
        final from = steps[i];
        final to = steps[i + 1];
        if (from.reached && to.reached &&
            from.timestamp != null && to.timestamp != null) {
          tiles.add(_DurationBadge(from: from.timestamp!, to: to.timestamp!));
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مسار الحالة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            ...tiles,
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
  final String? notes;
  final bool reached;

  const _TimelineStep({
    required this.label,
    required this.icon,
    required this.color,
    required this.timestamp,
    required this.performer,
    this.notes,
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
    final s = l.second.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year}  $h:$m:$s';
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
                  if (step.notes != null && step.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'ملاحظة: ${step.notes!}',
                        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
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

class _DurationBadge extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  const _DurationBadge({required this.from, required this.to});

  String _fmtDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} ثانية';
    if (d.inMinutes < 60) {
      final mins = d.inMinutes;
      final secs = d.inSeconds % 60;
      return secs == 0 ? '$mins دقيقة' : '$mins دقيقة $secs ثانية';
    }
    if (d.inHours < 24) {
      final h = d.inHours;
      final m = d.inMinutes % 60;
      return m == 0 ? '$h ساعة' : '$h ساعة $m دقيقة';
    }
    final days = d.inDays;
    final h = d.inHours % 24;
    return h == 0 ? '$days يوم' : '$days يوم $h ساعة';
  }

  @override
  Widget build(BuildContext context) {
    final label = _fmtDuration(to.difference(from).abs());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Vertical connector aligned with the circle centre (radius 16 → width 32)
          SizedBox(
            width: 32,
            child: Center(
              child: Container(width: 2, height: 24, color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
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
  final OrderStatus orderStatus;
  final OrderDirection orderDirection;
  final Map<String, String> receipts;
  final Map<String, InventoryItem> stockItems;
  const _ItemsCard({
    required this.items,
    required this.orderStatus,
    required this.orderDirection,
    required this.receipts,
    this.stockItems = const {},
  });

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    final s = l.second.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year}  $h:$m:$s';
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
            ...items.map((item) => _ItemRow(
              item: item,
              fmt: _fmt,
              orderStatus: orderStatus,
              receipts: receipts,
              invItem: orderDirection == OrderDirection.outbound
                  ? stockItems[item.inventoryId]
                  : null,
            )),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final OrderItem item;
  final String Function(DateTime?) fmt;
  final OrderStatus orderStatus;
  final Map<String, String> receipts;
  final InventoryItem? invItem;
  const _ItemRow({
    required this.item,
    required this.fmt,
    required this.orderStatus,
    required this.receipts,
    this.invItem,
  });

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
                Text(
                  item.finalQuantity != null
                      ? 'الكمية: ${item.finalQuantity} (مطلوب: ${item.quantity})'
                      : 'الكمية: ${item.quantity}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (!item.isCustom &&
                    orderStatus != OrderStatus.delivered &&
                    orderStatus != OrderStatus.deliveredToStorage &&
                    invItem != null &&
                    invItem!.quantity < item.effectiveQuantity)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            InventoryItemDetailScreen(item: invItem!),
                      ),
                    ),
                    child: Chip(
                      avatar: const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 16),
                      label: Text('المتوفر فقط: ${invItem!.quantity}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange)),
                      backgroundColor:
                          Colors.orange.withValues(alpha: 0.1),
                      side: BorderSide(
                          color: Colors.orange.withValues(alpha: 0.4)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (!item.isCustom &&
                    !(item.checkStatus == ItemCheckStatus.pending &&
                        orderStatus == OrderStatus.delivered)) ...[
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
          if (item.isCustom)
            _ReceiptIcon(receiptUrl: receipts[item.id]),
        ],
      ),
    );
  }
}

class _ReceiptIcon extends StatelessWidget {
  final String? receiptUrl;
  const _ReceiptIcon({this.receiptUrl});

  @override
  Widget build(BuildContext context) {
    if (receiptUrl != null) {
      return IconButton(
        icon: const Icon(Icons.receipt_long, color: Colors.green),
        tooltip: 'عرض الإيصال',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReceiptViewerScreen(url: receiptUrl!)),
        ),
      );
    }
    return const Icon(
      Icons.receipt_long_outlined,
      color: Colors.grey,
    );
  }
}

// ── Edit History Section ─────────────────────────────────────────────────────

class _EditHistorySection extends StatefulWidget {
  final String orderId;
  const _EditHistorySection({required this.orderId});

  @override
  State<_EditHistorySection> createState() => _EditHistorySectionState();
}

class _EditHistorySectionState extends State<_EditHistorySection> {
  final OrderRepository _repo = OrderRepository();
  List<OrderEditLogEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEditLog();
  }

  Future<void> _loadEditLog() async {
    final result = await _repo.fetchEditLog(widget.orderId);
    if (!mounted) return;
    switch (result) {
      case AppSuccess(:final data):
        setState(() { _entries = data; _isLoading = false; });
      case AppFailure():
        setState(() => _isLoading = false);
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year}  $h:$m';
  }

  String _changeLabel(Map<String, dynamic> change) {
    final action = change['action'] as String? ?? '';
    final name = change['item_name'] as String? ?? '';
    switch (action) {
      case 'update_quantity':
        return '$name: ${change['old_quantity']} → ${change['new_quantity']}';
      case 'remove_item':
        return 'حذف $name (كمية: ${change['quantity']})';
      case 'add_item':
        final custom = change['is_custom'] == true ? ' (مخصص)' : '';
        return 'إضافة $name$custom (كمية: ${change['quantity']})';
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    if (_entries.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'سجل التعديلات',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.blue.shade800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_entries.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._entries.map((entry) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        entry.performer?.fullName ?? 'مجهول',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      Text(
                        _fmt(entry.serverTimestamp),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.format_quote, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.reason,
                            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...entry.changes.map((change) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          change['action'] == 'remove_item'
                              ? Icons.remove_circle_outline
                              : change['action'] == 'add_item'
                                  ? Icons.add_circle_outline
                                  : Icons.edit_outlined,
                          size: 14,
                          color: change['action'] == 'remove_item'
                              ? Colors.red
                              : change['action'] == 'add_item'
                                  ? Colors.green
                                  : Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _changeLabel(change),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// ── Communication History Section ─────────────────────────────────────────────

class _CommunicationHistorySection extends StatefulWidget {
  final String orderId;
  const _CommunicationHistorySection({required this.orderId});

  @override
  State<_CommunicationHistorySection> createState() =>
      _CommunicationHistorySectionState();
}

class _CommunicationHistorySectionState
    extends State<_CommunicationHistorySection> {
  late final Future<List<ChatMessage>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHistory();
  }

  Future<List<ChatMessage>> _loadHistory() async {
    final result = await sl<ChatRepository>().getOrderCommunicationHistory(widget.orderId);
    return switch (result) {
      AppSuccess(:final data) => data,
      AppFailure() => [],
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChatMessage>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final history = snap.data ?? [];
        if (history.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  'سجل التواصل (${history.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...history.map((msg) => _CommHistoryTile(msg: msg)),
          ],
        );
      },
    );
  }
}

class _CommHistoryTile extends StatelessWidget {
  final ChatMessage msg;
  const _CommHistoryTile({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: msg.isUrgent
            ? Icon(Icons.priority_high, color: Colors.orange.shade700)
            : const Icon(Icons.chat_bubble_outline, color: Colors.blueGrey),
        title: Text(
          msg.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '${msg.senderName} · ${msg.threadTitle ?? ''} · ${_fmt(msg.createdAt)}',
          style: const TextStyle(fontSize: 11),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatThreadScreen(
              threadId: msg.threadId,
              threadTitle: msg.threadTitle ?? '',
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
