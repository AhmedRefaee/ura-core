import 'package:flutter/material.dart';
import '../../../shared/models/delivery_receipt.dart';

/// Fixed semantic colors (not theme-derived) so «بانتظار الاعتماد» / «معتمد» /
/// «مرفوض» read the same everywhere a سند from an outside entity shows up.
({String label, Color color, IconData icon}) receiptStatusStyle(ReceiptStatus status) => switch (status) {
      ReceiptStatus.pending => (
          label: 'بانتظار الاعتماد',
          color: const Color(0xFFE08A00),
          icon: Icons.hourglass_top_rounded,
        ),
      ReceiptStatus.approved => (
          label: 'معتمد',
          color: const Color(0xFF2E7D32),
          icon: Icons.check_circle_outline,
        ),
      ReceiptStatus.rejected => (
          label: 'مرفوض',
          color: const Color(0xFFC62828),
          icon: Icons.cancel_outlined,
        ),
    };

class ReceiptStatusChip extends StatelessWidget {
  final ReceiptStatus status;
  const ReceiptStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final style = receiptStatusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        border: Border.all(color: style.color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.color),
          const SizedBox(width: 4),
          Text(
            style.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: style.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
