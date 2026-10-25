import 'package:flutter/material.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/draft_order_item.dart';
import 'order_items_table.dart';

/// Adds typed lines to an order that already exists (edit order). The same
/// table create order uses; pops with the lines, or null when cancelled.
class TypedItemsPage extends StatefulWidget {
  const TypedItemsPage({super.key});

  @override
  State<TypedItemsPage> createState() => _TypedItemsPageState();
}

class _TypedItemsPageState extends State<TypedItemsPage> {
  // Starts with one empty line: the verifier came here to write something.
  final _items = <DraftOrderItem>[DraftOrderItem.typed(name: '', quantity: 1)];

  @override
  Widget build(BuildContext context) {
    final ready = _items.isNotEmpty && _items.every((i) => i.isComplete);
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة أصناف')),
      body: SingleChildScrollView(
        padding: AppSpacing.allLarge,
        child: OrderItemsTable(
          items: _items,
          onAddTyped: (lines) => setState(() => _items.addAll([
                for (final l in lines)
                  DraftOrderItem.typed(name: l.name, unit: l.unit, quantity: l.quantity),
              ])),
          onEditTyped: (i, {name, unit, quantity}) => setState(() =>
              _items[i] = _items[i].withTyped(name: name, unit: unit, quantity: quantity)),
          onQuantityChanged: (i, q) => setState(() => _items[i] = _items[i].withQuantity(q)),
          onRemove: (i) => setState(() => _items.removeAt(i)),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.allLarge,
          child: FilledButton.icon(
            onPressed: ready ? () => Navigator.pop(context, List.of(_items)) : null,
            icon: const Icon(Icons.playlist_add),
            label: Text('إضافة ${_items.length} للطلب'),
          ),
        ),
      ),
    );
  }
}
