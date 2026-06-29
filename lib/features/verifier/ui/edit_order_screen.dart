import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../logic/edit_order_cubit.dart';
import 'widgets/add_item_sheet.dart';
import '../../../core/design_system/theme/theme.dart';

class EditOrderScreen extends StatelessWidget {
  const EditOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<EditOrderCubit, EditOrderState>(
      listenWhen: (prev, curr) {
        if (curr is EditOrderSuccess || curr is EditOrderError) return true;
        if (curr is EditOrderReady && curr.stockError != null) {
          final prevErr = prev is EditOrderReady ? prev.stockError : null;
          return curr.stockError != prevErr;
        }
        return false;
      },
      listener: (context, state) {
        if (state is EditOrderSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تعديل الطلب بنجاح')),
          );
          Navigator.pop(context, true);
        }
        if (state is EditOrderError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        if (state is EditOrderReady && state.stockError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.stockError!),
              backgroundColor: Colors.orange,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is EditOrderInitial || state is EditOrderLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is EditOrderError && state is! EditOrderReady) {
          return Scaffold(
            appBar: AppBar(title: const Text('تعديل الطلب')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  SizedBox(height: AppSpacing.verticalMedium),
                  FilledButton(
                    onPressed: () =>
                        context.read<EditOrderCubit>().loadOrder(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final ready = state is EditOrderReady ? state : null;
        final isSubmitting = state is EditOrderSubmitting;

        return Scaffold(
          appBar: AppBar(title: const Text('تعديل الطلب')),
          body: ready == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: AppSpacing.allLarge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Order info header
                      _OrderInfoHeader(order: ready.originalOrder),
                      SizedBox(height: AppSpacing.verticalXLarge),

                      // Current items
                      Row(
                        children: [
                          const _SectionTitle('الأصناف الحالية'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showAddItemSheet(context, ready),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      ...ready.effectiveItems.map(
                        (item) => _EditableItemTile(
                          item: item,
                          isRemoved: ready.pendingActions.any(
                              (a) => a is RemoveItemAction && a.itemId == item.id),
                          inventory: ready.inventory,
                          onQuantityChanged: (qty) => context
                              .read<EditOrderCubit>()
                              .updateItemQuantity(item.id, qty),
                          onRemove: () =>
                              context.read<EditOrderCubit>().removeItem(item.id),
                        ),
                      ),

                      // Added items (from AddItemAction)
                      if (ready.addedItems.isNotEmpty) ...[
                        SizedBox(height: AppSpacing.verticalMedium),
                        const _SectionTitle('أصناف مضافة'),
                        ...ready.addedItems.map((draft) => ListTile(
                              dense: true,
                              leading: Icon(
                                draft.isCustom
                                    ? Icons.shopping_bag_outlined
                                    : Icons.inventory_2_outlined,
                                color: draft.isCustom ? Colors.orange : Colors.teal,
                                size: 20,
                              ),
                              title: Text(draft.displayName),
                              subtitle: Text('الكمية: ${formatQty(draft.quantity)}'),
                              trailing: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.horizontalXSmall, vertical: AppSpacing.verticalXSmall),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('جديد',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold)),
                              ),
                            )),
                      ],

                      SizedBox(height: AppSpacing.verticalXLarge),

                      // Pending changes summary
                      if (ready.pendingActions.isNotEmpty) ...[
                        const _SectionTitle('ملخص التغييرات'),
                        _ChangesSummaryCard(
                          actions: ready.pendingActions,
                          onUndo: (index) =>
                              context.read<EditOrderCubit>().undoAction(index),
                        ),
                        SizedBox(height: AppSpacing.verticalXLarge),
                      ],

                      // Reason field (required)
                      const _SectionTitle('سبب التعديل *'),
                      TextField(
                        maxLines: 2,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'مثال: تفاوض مع العميل، تعديل الكمية...',
                        ),
                        onChanged: (v) =>
                            context.read<EditOrderCubit>().setReason(v),
                      ),
                      SizedBox(height: AppSpacing.verticalXXXLarge),

                      FilledButton(
                        onPressed: isSubmitting || !(ready.canSubmit)
                            ? null
                            : () => context.read<EditOrderCubit>().submit(),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('حفظ التعديلات'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _showAddItemSheet(BuildContext context, EditOrderReady state) {
    final cubit = context.read<EditOrderCubit>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemSheet(
          inventory: state.inventory,
          orderDirection: state.originalOrder.direction,
          onAddInventoryItems: (items) {
            for (final entry in items) {
              cubit.addInventoryItem(entry.item, entry.quantity);
            }
          },
          onAddCustomItem: (desc, qty, {sourceInventoryId}) =>
              cubit.addCustomItem(desc, qty, sourceInventoryId: sourceInventoryId),
        ),
      ),
    );
  }
}

// ── Private Widgets ───────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class _OrderInfoHeader extends StatelessWidget {
  final Order order;
  const _OrderInfoHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                SizedBox(width: AppSpacing.horizontalSmall),
                Text('طلب ${order.directionLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: AppSpacing.verticalSmall),
            if (order.entity != null)
              Text('الجهة: ${order.entity!.name}',
                  style: const TextStyle(fontSize: 13)),
            if (order.rep != null)
              Text('المندوب: ${order.rep!.fullName}',
                  style: const TextStyle(fontSize: 13)),
            Text('الحالة: ${order.statusLabel}',
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _EditableItemTile extends StatelessWidget {
  final OrderItem item;
  final bool isRemoved;
  final List<InventoryItem> inventory;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback onRemove;

  const _EditableItemTile({
    required this.item,
    required this.isRemoved,
    required this.inventory,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (isRemoved) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
        title: Text(
          item.displayName,
          style: const TextStyle(
            decoration: TextDecoration.lineThrough,
            color: Colors.grey,
          ),
        ),
        subtitle: Text('الكمية: ${formatQty(item.quantity)}',
            style: const TextStyle(color: Colors.grey)),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalXSmall, vertical: AppSpacing.verticalXSmall),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('محذوف',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  fontWeight: FontWeight.bold)),
        ),
      );
    }

    // Find stock info for inventory items
    InventoryItem? invItem;
    if (item.inventoryId != null) {
      final matches = inventory.where((i) => i.id == item.inventoryId);
      if (matches.isNotEmpty) invItem = matches.first;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.verticalXSmall),
      child: Row(
        children: [
          Icon(
            item.isCustom ? Icons.shopping_bag_outlined : Icons.inventory_2_outlined,
            color: item.isCustom ? Colors.orange : Colors.teal,
            size: 20,
          ),
          SizedBox(width: AppSpacing.horizontalSmall),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(item.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (invItem != null)
                  Text(
                    'المتوفر: ${formatQty(invItem.quantity)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: invItem.availabilityStatus == AvailabilityStatus.outOfStock
                          ? Colors.red
                          : invItem.availabilityStatus == AvailabilityStatus.low
                              ? Colors.orange
                              : Colors.green,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: _QuantityField(
              initialValue: item.quantity,
              onChanged: onQuantityChanged,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _QuantityField extends StatefulWidget {
  final double initialValue;
  final ValueChanged<double> onChanged;

  const _QuantityField({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<_QuantityField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatQty(widget.initialValue));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [quantityInputFormatter],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalSmall, vertical: AppSpacing.horizontalSmall),
        isDense: true,
      ),
      onChanged: (v) {
        final qty = double.tryParse(v);
        if (qty != null && qty > 0) {
          widget.onChanged(qty);
        }
      },
    );
  }
}

class _ChangesSummaryCard extends StatelessWidget {
  final List<EditAction> actions;
  final ValueChanged<int> onUndo;

  const _ChangesSummaryCard({
    required this.actions,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.withValues(alpha: 0.08),
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 18, color: Colors.amber),
                SizedBox(width: AppSpacing.horizontalSmall),
                Text('${actions.length} تغيير',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: AppSpacing.verticalSmall),
            ...actions.asMap().entries.map((entry) {
              final i = entry.key;
              final action = entry.value;
              return Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.verticalXSmall),
                child: Row(
                  children: [
                    Expanded(child: Text(_actionLabel(action),
                        style: const TextStyle(fontSize: 13))),
                    IconButton(
                      icon: const Icon(Icons.undo, size: 16),
                      onPressed: () => onUndo(i),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'تراجع',
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _actionLabel(EditAction action) {
    switch (action) {
      case UpdateQuantityAction(:final itemName, :final oldQuantity, :final newQuantity):
        return '📝 $itemName: ${formatQty(oldQuantity)} → ${formatQty(newQuantity)}';
      case RemoveItemAction(:final itemName, :final quantity):
        return '🗑️ حذف $itemName (كمية: ${formatQty(quantity)})';
      case AddItemAction(:final item):
        return '➕ إضافة ${item.displayName} (كمية: ${formatQty(item.quantity)})';
    }
  }
}
