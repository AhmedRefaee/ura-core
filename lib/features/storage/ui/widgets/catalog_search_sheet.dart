import 'package:flutter/material.dart';
import '../../../../core/text/arabic_text.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/models/order_item.dart';
import '../../../../shared/utils/quantity_format.dart';

/// Storage swaps an order line to another catalog row: [quantity] restates
/// the line in the new row's unit when the units differ; null keeps it.
typedef CatalogSwap = ({InventoryItem item, double? quantity});

/// Opens a catalog search to point [item] at a different row. Null when
/// storage backed out.
Future<CatalogSwap?> showCatalogSwapSheet(
  BuildContext context, {
  required OrderItem item,
  required Future<List<InventoryItem>> Function() loadInventory,
}) =>
    showModalBottomSheet<CatalogSwap>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _CatalogSwapSheet(item: item, loadInventory: loadInventory),
      ),
    );

class _CatalogSwapSheet extends StatefulWidget {
  final OrderItem item;
  final Future<List<InventoryItem>> Function() loadInventory;

  const _CatalogSwapSheet({required this.item, required this.loadInventory});

  @override
  State<_CatalogSwapSheet> createState() => _CatalogSwapSheetState();
}

class _CatalogSwapSheetState extends State<_CatalogSwapSheet> {
  late final Future<List<InventoryItem>> _inventory = widget.loadInventory();

  Future<void> _pick(InventoryItem inv) async {
    if (inv.id == widget.item.inventoryId) {
      Navigator.pop(context);
      return;
    }
    final quantity = await askQuantityInUnit(
      context,
      inv: inv,
      fromUnit: widget.item.inventoryUnit ?? widget.item.typedUnit,
      fromQuantity: widget.item.quantity,
    );
    if (quantity == UnitQuantity.cancelled) return;
    if (mounted) Navigator.pop(context, (item: inv, quantity: quantity.value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FutureBuilder<List<InventoryItem>>(
        future: _inventory,
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('تغيير الصنف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('الحالي: ${widget.item.displayName} — ${formatQty(widget.item.quantity)}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            CatalogSearchList(snapshot: snap, onPick: _pick),
          ],
        ),
      ),
    );
  }
}

/// Searchable list of catalog rows (name, brand, variety, aliases), capped at
/// 50 results. [snapshot] is the caller's inventory load.
class CatalogSearchList extends StatefulWidget {
  final AsyncSnapshot<List<InventoryItem>> snapshot;
  final ValueChanged<InventoryItem> onPick;

  const CatalogSearchList({super.key, required this.snapshot, required this.onPick});

  @override
  State<CatalogSearchList> createState() => _CatalogSearchListState();
}

class _CatalogSearchListState extends State<CatalogSearchList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    if (snap.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (snap.hasError) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('تعذر تحميل أصناف المخزن', style: TextStyle(color: Colors.red)),
      );
    }
    final inventory = snap.data ?? const <InventoryItem>[];
    final q = ArabicText.normalize(_search.text.trim());
    final results = q.isEmpty
        ? inventory
        : inventory.where((i) => [
              i.itemName,
              i.brand ?? '',
              i.variety ?? '',
              ...?i.aliases,
            ].any((t) => ArabicText.normalize(t).contains(q))).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث في المخزن...',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('لا توجد نتائج', style: TextStyle(color: Colors.grey)),
          ),
        // Capped: the sheet scrolls as a whole, and nobody scrolls past 50.
        for (final inv in results.take(50))
          ListTile(
            dense: true,
            title: Text(inv.itemName),
            subtitle: Text([inv.brand, inv.variety].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
            trailing: Text('${formatQty(inv.quantity)} ${inv.unit}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            onTap: () => widget.onPick(inv),
          ),
      ],
    );
  }
}

/// Result of [askQuantityInUnit]: [value] null means "keep the quantity".
class UnitQuantity {
  final double? value;
  const UnitQuantity._(this.value);
  static const keep = UnitQuantity._(null);
  static const cancelled = UnitQuantity._(-1);
}

/// A different unit means a different number: "2 كرتون" is not 2 حبة. When
/// [fromUnit] differs from [inv]'s unit, asks how many of [inv]'s unit the line
/// means; otherwise keeps the quantity without asking.
Future<UnitQuantity> askQuantityInUnit(
  BuildContext context, {
  required InventoryItem inv,
  required String? fromUnit,
  required double fromQuantity,
}) async {
  final unit = fromUnit?.trim();
  if (unit == null || unit.isEmpty || unit == inv.unit.trim()) return UnitQuantity.keep;
  final q = await showDialog<double>(
    context: context,
    builder: (_) => _QuantityDialog(inv: inv, fromUnit: unit, fromQuantity: fromQuantity),
  );
  return q == null ? UnitQuantity.cancelled : UnitQuantity._(q);
}

class _QuantityDialog extends StatefulWidget {
  final InventoryItem inv;
  final String fromUnit;
  final double fromQuantity;

  const _QuantityDialog({required this.inv, required this.fromUnit, required this.fromQuantity});

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: formatQty(widget.fromQuantity));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (q != null && q > 0) Navigator.pop(context, q);
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    return AlertDialog(
      title: const Text('الكمية بوحدة المخزن'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المطلوب: ${formatQty(widget.fromQuantity)} ${widget.fromUnit}'),
          const SizedBox(height: 4),
          Text('"${inv.itemName}" يُحسب بـ ${inv.unit} — كم ${inv.unit} تعني؟',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [quantityInputFormatter],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixText: inv.unit,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('ربط')),
      ],
    );
  }
}
