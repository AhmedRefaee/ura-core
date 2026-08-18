import 'package:flutter/material.dart';
import '../../features/inventory/ui/inventory_item_detail_screen.dart';
import '../models/draft_order_item.dart';
import '../models/inventory_item.dart';
import '../models/order.dart';
import '../utils/quantity_format.dart';

class DraftOrderItemsList extends StatelessWidget {
  final List<DraftOrderItem> items;
  final List<InventoryItem> inventory;
  final OrderDirection direction;
  final ValueChanged<int> onRemove;

  const DraftOrderItemsList({
    super.key,
    required this.items,
    required this.inventory,
    required this.direction,
    required this.onRemove,
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
    return Column(
      children: [
        for (int i = 0; i < items.length; i++)
          _buildItemTile(context, i, items[i]),
      ],
    );
  }

  Widget _buildItemTile(BuildContext context, int index, DraftOrderItem item) {
    final invItem =
        direction == OrderDirection.outbound && item.inventoryId != null
        ? inventory.where((inv) => inv.id == item.inventoryId).firstOrNull
        : null;
    final isOverStock = invItem != null && item.quantity > invItem.quantity;

    return ListTile(
      dense: true,
      title: Text(item.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('الكمية: ${formatQty(item.quantity)}'),
          if (isOverStock)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventoryItemDetailScreen(item: invItem),
                ),
              ),
              child: Chip(
                avatar: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 16,
                ),
                label: Text(
                  'المتوفر فقط: ${formatQty(invItem.quantity)}',
                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                ),
                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: () => onRemove(index),
      ),
    );
  }
}
