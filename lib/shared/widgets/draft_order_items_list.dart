import 'package:flutter/material.dart';
import '../models/draft_order_item.dart';
import '../models/off_stock_kind.dart';
import '../utils/quantity_format.dart';
import 'off_stock.dart';

class DraftOrderItemsList extends StatelessWidget {
  final List<DraftOrderItem> items;
  final ValueChanged<int> onRemove;

  /// Opens an off-stock item for editing so its brand, variety, packaging and
  /// unit can be filled in before the order is submitted. Optional: the
  /// template editor reuses this list but has no such flow, and passes null,
  /// which simply hides the affordance.
  final ValueChanged<int>? onEditCustom;

  const DraftOrderItemsList({
    super.key,
    required this.items,
    required this.onRemove,
    this.onEditCustom,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'لم يتم إضافة أصناف بعد',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    // Split by index, not by value, so onRemove keeps pointing at the right
    // slot in the original list once the two groups are rendered separately.
    final stockIndices = <int>[];
    final offStockIndices = <int>[];
    for (var i = 0; i < items.length; i++) {
      (_kindOf(items[i]) == null ? stockIndices : offStockIndices).add(i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in stockIndices) _buildItemTile(context, i, items[i]),
        if (offStockIndices.isNotEmpty)
          OffStock.section(
            count: offStockIndices.length,
            child: Column(
              children: [
                for (final i in offStockIndices) _buildItemTile(context, i, items[i]),
              ],
            ),
          ),
      ],
    );
  }

  OffStockKind? _kindOf(DraftOrderItem item) => draftOffStockKind(
        isCustom: item.isCustom,
        sourceInventoryId: item.sourceInventoryId,
      );

  Widget _buildItemTile(BuildContext context, int index, DraftOrderItem item) {
    final kind = _kindOf(item);
    return ListTile(
      dense: true,
      title: Text(item.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('الكمية: ${formatQty(item.quantity)}'),
          if (kind != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: OffStock.badge(kind),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.isCustom && onEditCustom != null)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: OffStock.color),
              tooltip: 'تعديل بيانات الصنف',
              visualDensity: VisualDensity.compact,
              onPressed: () => onEditCustom!(index),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'حذف',
            visualDensity: VisualDensity.compact,
            onPressed: () => onRemove(index),
          ),
        ],
      ),
    );
  }
}
