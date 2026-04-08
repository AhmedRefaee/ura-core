import 'package:flutter/material.dart';
import '../../../../shared/models/order.dart';

class OrderCard extends StatelessWidget {
  final Order order;
  const OrderCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(order.status),
                const SizedBox(width: 8),
                _DirectionChip(order.direction),
                const Spacer(),
                Text(
                  order.entity?.name ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (order.rep != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    order.rep!.fullName,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
            if (order.items.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${order.items.length} أصناف',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
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
    );
  }
}

class _StatusChip extends StatelessWidget {
  final OrderStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case OrderStatus.assigned:
        color = Colors.orange;
      case OrderStatus.pickedUp:
        color = Colors.blue;
      case OrderStatus.onTheMove:
        color = Colors.purple;
      case OrderStatus.delivered:
        color = Colors.green;
    }

    final labels = {
      OrderStatus.assigned: 'معين',
      OrderStatus.pickedUp: 'تم الاستلام',
      OrderStatus.onTheMove: 'في الطريق',
      OrderStatus.delivered: 'مُسلَّم',
    };

    return Chip(
      label: Text(labels[status]!, style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _DirectionChip extends StatelessWidget {
  final OrderDirection direction;
  const _DirectionChip(this.direction);

  @override
  Widget build(BuildContext context) {
    final labels = {
      OrderDirection.outbound: 'صادر',
      OrderDirection.inboundRep: 'وارد (مندوب)',
      OrderDirection.inboundExternal: 'وارد (خارجي)',
    };
    return Chip(
      label: Text(labels[direction]!, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
