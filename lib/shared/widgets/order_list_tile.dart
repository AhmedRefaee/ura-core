import 'package:flutter/material.dart';
import '../models/order.dart';
import '../order_status_theme.dart';

class OrderListTile extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  const OrderListTile({super.key, required this.order, this.onTap});

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
                    Text(
                      order.entity?.name ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.items.length} أصناف · ${order.directionLabel}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    if (order.notes != null && order.notes!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        order.notes!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            ],
          ),
        ),
      ),
    );
  }
}
