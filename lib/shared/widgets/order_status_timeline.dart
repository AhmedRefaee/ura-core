import 'package:flutter/material.dart';
import '../models/audit_log_entry.dart';
import '../models/order.dart';
import '../models/profile.dart';
import '../order_status_theme.dart';

class OrderStatusTimeline extends StatelessWidget {
  final Order order;
  final List<AuditLogEntry> auditLog;

  const OrderStatusTimeline({
    super.key,
    required this.order,
    required this.auditLog,
  });

  // Prefer an entry that has notes; fall back to any entry for that status.
  AuditLogEntry? _entryFor(OrderStatus status) {
    try {
      return auditLog.firstWhere(
        (e) => e.newStatus == status && e.notes != null && e.notes!.isNotEmpty,
      );
    } catch (_) {}
    try {
      return auditLog.firstWhere((e) => e.newStatus == status);
    } catch (_) {
      return null;
    }
  }

  // Verifier creation notes — stored via the orders_log_creation trigger.
  // Falls back to order.notes for orders created before the trigger existed.
  String? get _creationNotes {
    try {
      final entry = auditLog.firstWhere((e) => e.action == 'order_created');
      return entry.notes?.isNotEmpty == true ? entry.notes : order.notes;
    } catch (_) {
      return order.notes;
    }
  }

  DateTime? _overallDeliveredAt(List<_TimelineStep> steps) {
    if (order.status != OrderStatus.delivered &&
        order.status != OrderStatus.deliveredToStorage) {
      return null;
    }
    for (final step in steps.reversed) {
      if (step.countsAsDelivery && step.reached && step.timestamp != null) {
        return step.timestamp;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pickedUpEntry = _entryFor(OrderStatus.pickedUp);
    final onTheMoveEntry = _entryFor(OrderStatus.onTheMove);
    final deliveredEntry = _entryFor(OrderStatus.delivered);
    final deliveredToStorageEntry = _entryFor(OrderStatus.deliveredToStorage);

    final dir = order.direction;
    final status = order.status;

    List<_TimelineStep> steps;

    if (dir == OrderDirection.inboundExternal) {
      steps = [
        _TimelineStep(
          label: 'تم الإنشاء',
          icon: OrderStatus.assigned.icon,
          color: OrderStatus.assigned.color,
          timestamp: order.assignedAt ?? order.createdAt,
          performer: order.creator,
          notes: _creationNotes,
          reached: true,
        ),
        _TimelineStep(
          label: 'تم الاستلام في المخزن',
          icon: OrderStatus.deliveredToStorage.icon,
          color: OrderStatus.deliveredToStorage.color,
          timestamp: order.deliveredAt ?? deliveredEntry?.serverTimestamp,
          performer: deliveredEntry?.performer,
          notes: deliveredEntry?.notes,
          countsAsDelivery: true,
          reached:
              status == OrderStatus.delivered ||
              status == OrderStatus.deliveredToStorage,
        ),
      ];
    } else if (dir == OrderDirection.inboundRep) {
      steps = [
        _TimelineStep(
          label: 'تم الإنشاء',
          icon: OrderStatus.assigned.icon,
          color: OrderStatus.assigned.color,
          timestamp: order.assignedAt ?? order.createdAt,
          performer: order.creator,
          notes: _creationNotes,
          reached: true,
        ),
        _TimelineStep(
          label: 'تم الشراء',
          icon: OrderStatus.pickedUp.icon,
          color: OrderStatus.pickedUp.color,
          timestamp: order.pickedUpAt,
          performer: pickedUpEntry?.performer,
          notes: pickedUpEntry?.notes,
          reached: status != OrderStatus.assigned,
        ),
        _TimelineStep(
          label: 'في الطريق إلى المخزن',
          icon: OrderStatus.onTheMove.icon,
          color: OrderStatus.onTheMove.color,
          timestamp: order.moveStartedAt ?? onTheMoveEntry?.serverTimestamp,
          performer: onTheMoveEntry?.performer,
          notes: onTheMoveEntry?.notes,
          reached:
              status == OrderStatus.onTheMove ||
              status == OrderStatus.delivered ||
              status == OrderStatus.deliveredToStorage,
        ),
        _TimelineStep(
          label: 'استلام المخزن',
          icon: OrderStatus.deliveredToStorage.icon,
          color: OrderStatus.deliveredToStorage.color,
          timestamp:
              deliveredToStorageEntry?.serverTimestamp ??
              order.deliveredAt ??
              deliveredEntry?.serverTimestamp,
          performer:
              deliveredToStorageEntry?.performer ?? deliveredEntry?.performer,
          notes: deliveredToStorageEntry?.notes ?? deliveredEntry?.notes,
          countsAsDelivery: true,
          reached:
              status == OrderStatus.delivered ||
              status == OrderStatus.deliveredToStorage,
        ),
      ];
    } else {
      // outbound
      steps = [
        _TimelineStep(
          label: 'تم الإنشاء',
          icon: OrderStatus.assigned.icon,
          color: OrderStatus.assigned.color,
          timestamp: order.assignedAt ?? order.createdAt,
          performer: order.creator,
          notes: _creationNotes,
          reached: true,
        ),
        _TimelineStep(
          label: order.involvesStorage
              ? 'تم الاستلام من المخزن'
              : 'تم الاستلام',
          icon: OrderStatus.pickedUp.icon,
          color: OrderStatus.pickedUp.color,
          timestamp: order.pickedUpAt,
          performer: pickedUpEntry?.performer,
          notes: pickedUpEntry?.notes,
          reached: status != OrderStatus.assigned,
        ),
        _TimelineStep(
          label: 'في الطريق',
          icon: OrderStatus.onTheMove.icon,
          color: OrderStatus.onTheMove.color,
          timestamp: order.moveStartedAt ?? onTheMoveEntry?.serverTimestamp,
          performer: onTheMoveEntry?.performer,
          notes: onTheMoveEntry?.notes,
          reached:
              status == OrderStatus.onTheMove ||
              status == OrderStatus.delivered,
        ),
        _TimelineStep(
          label: 'تم التسليم',
          icon: OrderStatus.delivered.icon,
          color: OrderStatus.delivered.color,
          timestamp: order.deliveredAt ?? deliveredEntry?.serverTimestamp,
          performer: deliveredEntry?.performer,
          notes: deliveredEntry?.notes,
          countsAsDelivery: true,
          reached: status == OrderStatus.delivered,
        ),
      ];
    }

    final List<Widget> tiles = [];
    for (int i = 0; i < steps.length; i++) {
      tiles.add(_StepTile(step: steps[i]));
      if (i < steps.length - 1) {
        final from = steps[i];
        final to = steps[i + 1];
        tiles.add(_StepConnector(from: from, to: to));
      }
    }

    final overallDeliveredAt = _overallDeliveredAt(steps);
    final overallDuration =
        order.createdAt != null && overallDeliveredAt != null
        ? overallDeliveredAt.difference(order.createdAt!).abs()
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'مسار الحالة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            if (overallDuration != null) ...[
              _OverallDurationBadge(duration: overallDuration),
              const SizedBox(height: 12),
            ],
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
  final bool countsAsDelivery;
  final bool reached;

  const _TimelineStep({
    required this.label,
    required this.icon,
    required this.color,
    required this.timestamp,
    required this.performer,
    this.notes,
    this.countsAsDelivery = false,
    required this.reached,
  });
}

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

class _OverallDurationBadge extends StatelessWidget {
  final Duration duration;

  const _OverallDurationBadge({required this.duration});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'المدة الإجمالية من الإنشاء إلى التسليم',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtDuration(duration),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
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
                backgroundColor: active ? step.color : Colors.grey.shade300,
                child: Icon(
                  step.icon,
                  size: 16,
                  color: active ? Colors.white : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: active ? null : Colors.grey,
                  ),
                ),
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
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.notes,
                            size: 13,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              step.notes!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ] else
                  Text(
                    'لم يتم بعد',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  final _TimelineStep from;
  final _TimelineStep to;

  const _StepConnector({required this.from, required this.to});

  bool get _hasDuration =>
      from.reached &&
      to.reached &&
      from.timestamp != null &&
      to.timestamp != null;

  List<Color> get _colors {
    if (from.reached && to.reached) {
      return [from.color, to.color];
    }
    if (from.reached) {
      return [
        from.color.withValues(alpha: 0.72),
        to.color.withValues(alpha: 0.56),
      ];
    }
    return [
      from.color.withValues(alpha: 0.38),
      to.color.withValues(alpha: 0.38),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 6, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: colors,
              ),
              boxShadow: from.reached
                  ? [
                      BoxShadow(
                        color: colors.last.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          if (_hasDuration)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.last.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.last.withValues(alpha: 0.22)),
              ),
              child: Text(
                _fmtDuration(to.timestamp!.difference(from.timestamp!).abs()),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.last.withValues(alpha: 0.82),
                ),
              ),
            )
          else
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      colors.last.withValues(alpha: 0.25),
                      colors.last.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
