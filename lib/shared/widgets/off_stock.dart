import 'package:flutter/material.dart';
import '../models/off_stock_label.dart';

/// Everything about how an "outside inventory" item looks and reads, in one
/// place. `isCustom` on an order item has meant this since the model was
/// built; what was missing was a single definition of what to show for it,
/// so five screens each hand-picked `Colors.orange` and called it done — one
/// screen (the draft list while building an order) picked nothing at all, and
/// a custom item was indistinguishable from a real one right where getting
/// that distinction right matters most.
///
/// Deliberately not orange: this list already uses orange for "ordering more
/// than what's in stock", a warning about a real inventory row. An outside-
/// inventory item is not a warning, it is a different kind of thing, and
/// sharing a colour with an unrelated warning would make both harder to read.
class OffStock {
  const OffStock._();

  static const label = offStockLabel;
  static const explanation = 'لا يدخل المخزون — يسلّم مباشرة للجهة';
  static const icon = Icons.local_shipping_outlined;
  static const color = Colors.deepPurple;

  /// The small chip for one row.
  static Widget badge({double fontSize = 11}) => Chip(
        avatar: Icon(icon, color: color, size: fontSize + 5),
        label: Text(label, style: TextStyle(fontSize: fontSize, color: color)),
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );

  /// Wraps the outside-inventory rows of a list in a labelled, tinted section,
  /// set apart from the ordinary inventory rows above it rather than
  /// interleaved with them — the point is that a glance down the list tells
  /// you where "real stock" ends, not that you have to read every row's badge
  /// to find out.
  static Widget section({required int count, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  '$label · $count ${count == 1 ? 'صنف' : 'أصناف'}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 2),
            child: Text(
              explanation,
              style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
            ),
          ),
          child,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
