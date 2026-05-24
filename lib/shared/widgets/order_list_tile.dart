import 'package:flutter/material.dart';
import '../models/order.dart';
import '../order_status_theme.dart';

class GroupedOrderScope extends InheritedWidget {
  final bool insetCard;

  const GroupedOrderScope({
    super.key,
    required this.insetCard,
    required super.child,
  });

  static bool insetOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<GroupedOrderScope>();
    return scope?.insetCard ?? false;
  }

  @override
  bool updateShouldNotify(GroupedOrderScope oldWidget) =>
      insetCard != oldWidget.insetCard;
}

class OrderListTile extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  final ValueChanged<Order>? onCopy;
  const OrderListTile({
    super.key,
    required this.order,
    this.onTap,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;
    switch (order.direction) {
      case OrderDirection.inboundExternal:
        icon = Icons.local_shipping_outlined;
        iconColor = Colors.indigo;
      case OrderDirection.inboundRep:
        icon = Icons.download_outlined;
        iconColor = Colors.teal;
      case OrderDirection.outbound:
        icon = Icons.upload_outlined;
        iconColor = Colors.orange;
    }

    final statusColor = order.status.color;
    final orderDateLabel = _formatOrderDate(order.createdAt);
    final completionDurationLabel = _formatCompletionDuration(order);
    final inset = GroupedOrderScope.insetOf(context);

    return Card(
      margin: inset
          ? const EdgeInsets.symmetric(vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.referenceCode != null) ...[
                      Text(
                        order.referenceCode!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      order.entity?.name ?? '—',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.items.length} أصناف · ${order.directionLabel}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    if (orderDateLabel != null ||
                        completionDurationLabel != null) ...[
                      const SizedBox(height: 6),
                      _OrderMetaWrap(
                        orderDateLabel: orderDateLabel,
                        completionDurationLabel: completionDurationLabel,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: _StatusBadge(
                  label: order.statusLabel,
                  color: statusColor,
                ),
              ),
              if (onCopy != null)
                PopupMenuButton<String>(
                  tooltip: 'إجراءات',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'copy') onCopy!(order);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.content_copy_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('نسخ الطلب'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderGridCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  final ValueChanged<Order>? onCopy;

  const OrderGridCard({
    super.key,
    required this.order,
    this.onTap,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = order.status.color;
    final (icon, iconColor) = switch (order.direction) {
      OrderDirection.inboundExternal => (
        Icons.local_shipping_outlined,
        Colors.indigo,
      ),
      OrderDirection.inboundRep => (Icons.download_outlined, Colors.teal),
      OrderDirection.outbound => (Icons.upload_outlined, Colors.orange),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _StatusBadge(
                        label: order.statusLabel,
                        color: statusColor,
                        compact: true,
                      ),
                    ),
                  ),
                  if (onCopy != null)
                    PopupMenuButton<String>(
                      tooltip: 'إجراءات',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (value) {
                        if (value == 'copy') onCopy!(order);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.content_copy_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('نسخ الطلب'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (order.referenceCode != null) ...[
                const SizedBox(height: 8),
                Text(
                  order.referenceCode!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                order.entity?.name ?? '—',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                order.rep?.fullName ?? 'بدون مندوب',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              _OrderMetaWrap(
                orderDateLabel: _formatOrderDate(order.createdAt),
                completionDurationLabel: _formatCompletionDuration(order),
                compact: true,
              ),
              const Spacer(),
              Text(
                '${order.items.length} أصناف · ${order.directionLabel}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderMetaWrap extends StatelessWidget {
  final String? orderDateLabel;
  final String? completionDurationLabel;
  final bool compact;

  const _OrderMetaWrap({
    required this.orderDateLabel,
    required this.completionDurationLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (orderDateLabel == null && completionDurationLabel == null) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (orderDateLabel != null)
          _OrderMetaPill(
            icon: Icons.calendar_today_outlined,
            label: orderDateLabel!,
            compact: compact,
          ),
        if (completionDurationLabel != null)
          _OrderMetaPill(
            icon: Icons.timer_outlined,
            label: completionDurationLabel!,
            compact: compact,
          ),
      ],
    );
  }
}

class _OrderMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;

  const _OrderMetaPill({
    required this.icon,
    required this.label,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 12 : 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: compact ? 10 : 11, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;

  const _StatusBadge({
    required this.label,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 10 : 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

String? _formatOrderDate(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'تاريخ: ${local.day}/${local.month}/${local.year} $hour:$minute';
}

String? _formatCompletionDuration(Order order) {
  final deliveredAt = switch (order.status) {
    OrderStatus.delivered ||
    OrderStatus.deliveredToStorage => order.deliveredAt,
    _ => null,
  };
  if (order.createdAt == null || deliveredAt == null) return null;
  final duration = deliveredAt.difference(order.createdAt!).abs();
  return 'المدة: ${_formatDuration(duration)}';
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds < 60) return '${duration.inSeconds} ثانية';
  if (duration.inMinutes < 60) {
    return '${duration.inMinutes} دقيقة';
  }
  if (duration.inHours < 24) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return minutes == 0 ? '$hours ساعة' : '$hours ساعة $minutes دقيقة';
  }
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  return hours == 0 ? '$days يوم' : '$days يوم $hours ساعة';
}
