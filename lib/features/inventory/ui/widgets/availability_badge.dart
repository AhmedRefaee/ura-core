import 'package:flutter/material.dart';
import '../../../../shared/models/inventory_item.dart';

class AvailabilityBadge extends StatelessWidget {
  final AvailabilityStatus status;

  const AvailabilityBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    switch (status) {
      case AvailabilityStatus.available:
        color = Colors.green;
        label = 'متوفر';
        icon = Icons.check_circle_outline;
      case AvailabilityStatus.low:
        color = Colors.orange;
        label = 'منخفض';
        icon = Icons.warning_amber_outlined;
      case AvailabilityStatus.outOfStock:
        color = Colors.red;
        label = 'نفد';
        icon = Icons.cancel_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
