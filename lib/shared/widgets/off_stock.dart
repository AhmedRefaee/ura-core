import 'package:flutter/material.dart';
import '../models/off_stock_kind.dart';
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
///
/// The colour answers one question — *does the rep have to source this
/// himself?* — and [OffStockKind] answers the follow-up the verifier and the
/// storage actor need, which is *why*. Both kinds are the same purple on
/// purpose: to the rep they are the same job, and splitting the colour would
/// undo the thing the colour is for.
class OffStock {
  const OffStock._();

  static const label = offStockLabel;
  static const explanation = 'لا يدخل المخزون — يسلّم مباشرة للجهة';
  static const icon = Icons.local_shipping_outlined;
  static const color = Colors.deepPurple;

  /// The icon that tells the two kinds apart at a glance.
  static IconData iconFor(OffStockKind kind) => switch (kind) {
        OffStockKind.newItem => Icons.fiber_new_outlined,
        OffStockKind.outOfStock => Icons.remove_shopping_cart_outlined,
      };

  /// The short word appended to the badge, naming which kind this is.
  static String labelFor(OffStockKind kind) => switch (kind) {
        OffStockKind.newItem => 'جديد',
        OffStockKind.outOfStock => 'غير متوفر',
      };

  /// The one-line reason, for places with room to spell it out.
  static String explanationFor(OffStockKind kind) => switch (kind) {
        OffStockKind.newItem => 'غير موجود في المخزون أصلاً',
        OffStockKind.outOfStock => 'موجود في المخزون لكن الرصيد صفر',
      };

  /// The small chip for one row.
  ///
  /// [kind] is required rather than defaulted: a screen that does not say
  /// which kind it is showing is a screen that has not decided, and that is
  /// exactly how the out-of-stock case went unlabelled for so long.
  static Widget badge(OffStockKind kind, {double fontSize = 11}) => Chip(
        avatar: Icon(iconFor(kind), color: color, size: fontSize + 5),
        label: Text(
          '$label · ${labelFor(kind)}',
          style: TextStyle(fontSize: fontSize, color: color),
        ),
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
