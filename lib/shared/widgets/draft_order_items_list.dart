import 'package:flutter/material.dart';
import '../models/draft_order_item.dart';
import '../utils/quantity_format.dart';

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
    // One list, in the order the verifier added things. Whether an item is
    // in stock is storage's call now, so nothing here is grouped or painted
    // as "خارج المخزون" -- the only distinction left is a catalog row the
    // verifier matched versus a line they typed.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) _buildItemTile(context, i, items[i]),
      ],
    );
  }

  Widget _buildItemTile(BuildContext context, int index, DraftOrderItem item) {
    return ListTile(
      dense: true,
      leading: Icon(
        item.isCustom ? Icons.edit_note : Icons.inventory_2_outlined,
        color: item.isCustom ? Colors.grey : Colors.teal,
        size: 20,
      ),
      title: Text(item.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('الكمية: ${formatQty(item.quantity)}'),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.isCustom && onEditCustom != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
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
