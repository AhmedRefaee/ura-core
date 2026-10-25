import 'package:flutter/material.dart';
import '../../../../core/text/arabic_text.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/models/order_item.dart';
import '../../../../shared/utils/quantity_format.dart';

/// What storage decided for a typed line it has (✓).
sealed class TypedLineChoice {
  const TypedLineChoice();
}

/// It is this catalog row. [quantity] restates the line in the row's unit
/// when the verifier wrote another one; null keeps the typed quantity.
class LinkToCatalog extends TypedLineChoice {
  final InventoryItem item;
  final double? quantity;
  const LinkToCatalog(this.item, {this.quantity});
}

/// Not in the catalog yet: add it, and link the line to the new row.
class AddAsNewItem extends TypedLineChoice {
  const AddAsNewItem();
}

/// Available, nothing to link -- no stock moves.
class JustAvailable extends TypedLineChoice {
  const JustAvailable();
}

/// Catalog rows whose name or alias is *exactly* what the verifier typed,
/// once spelling variants are folded. No fuzzy matching: a suggestion here
/// is only ever something storage itself confirmed before (an alias is
/// written when a linked order is confirmed) or the very same name.
List<InventoryItem> rememberedLinks(String typedName, List<InventoryItem> inventory) {
  final typed = ArabicText.normalize(typedName.trim());
  if (typed.isEmpty) return const [];
  return [
    for (final item in inventory)
      if (ArabicText.normalize(item.itemName.trim()) == typed ||
          (item.aliases ?? const []).any((a) => ArabicText.normalize(a.trim()) == typed))
        item,
  ];
}

/// Opens the ✓ choices for a typed line. Null when storage backed out.
Future<TypedLineChoice?> showTypedLineReviewSheet(
  BuildContext context, {
  required OrderItem item,
  required Future<List<InventoryItem>> Function() loadInventory,
}) =>
    showModalBottomSheet<TypedLineChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: TypedLineReviewSheet(item: item, loadInventory: loadInventory),
      ),
    );

class TypedLineReviewSheet extends StatefulWidget {
  final OrderItem item;
  final Future<List<InventoryItem>> Function() loadInventory;

  const TypedLineReviewSheet({super.key, required this.item, required this.loadInventory});

  @override
  State<TypedLineReviewSheet> createState() => _TypedLineReviewSheetState();
}

class _TypedLineReviewSheetState extends State<TypedLineReviewSheet> {
  late final Future<List<InventoryItem>> _inventory = widget.loadInventory();
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _typedLine {
    final unit = widget.item.typedUnit;
    return '${widget.item.typedName} — ${formatQty(widget.item.quantity)}'
        '${unit != null && unit.isNotEmpty ? ' $unit' : ''}';
  }

  Future<void> _link(InventoryItem inv) async {
    final typedUnit = widget.item.typedUnit?.trim();
    double? quantity;
    // A different unit means a different number: "2 كرتون" is not 2 حبة.
    if (typedUnit != null && typedUnit.isNotEmpty && typedUnit != inv.unit.trim()) {
      quantity = await _askQuantity(inv, typedUnit);
      if (quantity == null) return;
    }
    if (mounted) Navigator.pop(context, LinkToCatalog(inv, quantity: quantity));
  }

  Future<double?> _askQuantity(InventoryItem inv, String typedUnit) => showDialog<double>(
        context: context,
        builder: (_) => _QuantityDialog(
          inv: inv,
          typedUnit: typedUnit,
          typedQuantity: widget.item.quantity,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FutureBuilder<List<InventoryItem>>(
        future: _inventory,
        builder: (context, snap) {
          final inventory = snap.data ?? const <InventoryItem>[];
          final remembered = rememberedLinks(widget.item.typedName, inventory);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('متوفر في المخزن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('كتب المدقق: $_typedLine', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              for (final inv in remembered)
                Card(
                  color: Colors.teal.withValues(alpha: 0.08),
                  child: ListTile(
                    leading: const Icon(Icons.history, color: Colors.teal),
                    title: Text('ربط بـ ${inv.itemName}'),
                    subtitle: const Text('نفس الاسم من مرة سابقة'),
                    trailing: Text(inv.unit),
                    onTap: () => _link(inv),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.link, color: Colors.teal),
                title: const Text('ربط بصنف في المخزن'),
                subtitle: const Text('يُخصم من رصيده عند التأكيد'),
                trailing: Icon(_searching ? Icons.expand_less : Icons.expand_more),
                onTap: () => setState(() => _searching = !_searching),
              ),
              if (_searching) _buildSearch(snap, inventory),
              ListTile(
                leading: const Icon(Icons.add_box_outlined, color: Colors.teal),
                title: const Text('إضافة كصنف جديد'),
                subtitle: const Text('غير موجود في المخزن بعد — يُضاف ويُربط'),
                onTap: () => Navigator.pop(context, const AddAsNewItem()),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: const Text('متوفر فقط'),
                subtitle: const Text('بدون ربط — لا يتغير رصيد المخزن'),
                onTap: () => Navigator.pop(context, const JustAvailable()),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearch(AsyncSnapshot<List<InventoryItem>> snap, List<InventoryItem> inventory) {
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
    final q = ArabicText.normalize(_search.text.trim());
    final results = q.isEmpty
        ? inventory
        : inventory.where((i) => [
              i.itemName,
              i.brand ?? '',
              i.variety ?? '',
              ...?i.aliases,
            ].any((t) => ArabicText.normalize(t).contains(q))).toList();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16),
      child: Column(
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
              onTap: () => _link(inv),
            ),
        ],
      ),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  final InventoryItem inv;
  final String typedUnit;
  final double typedQuantity;

  const _QuantityDialog({required this.inv, required this.typedUnit, required this.typedQuantity});

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: formatQty(widget.typedQuantity));

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
          Text('المطلوب: ${formatQty(widget.typedQuantity)} ${widget.typedUnit}'),
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
