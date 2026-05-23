import 'package:flutter/material.dart';
import '../models/order.dart';
import '../order_status_theme.dart';

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    if (order.notes != null && order.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        order.notes!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  border: Border.all(color: statusColor),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
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
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      border: Border.all(color: statusColor),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      order.statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
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
        Text(
          label,
          style: TextStyle(fontSize: compact ? 10 : 11, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
