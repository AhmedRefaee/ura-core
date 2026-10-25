import 'package:flutter/material.dart';
import '../../../../core/text/arabic_text.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/models/order_item.dart';
import '../../../../shared/utils/quantity_format.dart';
import 'catalog_search_sheet.dart';

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
  bool _searching = false;

  String get _typedLine {
    final unit = widget.item.typedUnit;
    return '${widget.item.typedName} — ${formatQty(widget.item.quantity)}'
        '${unit != null && unit.isNotEmpty ? ' $unit' : ''}';
  }

  Future<void> _link(InventoryItem inv) async {
    final quantity = await askQuantityInUnit(
      context,
      inv: inv,
      fromUnit: widget.item.typedUnit,
      fromQuantity: widget.item.quantity,
    );
    if (quantity == UnitQuantity.cancelled) return;
    if (mounted) Navigator.pop(context, LinkToCatalog(inv, quantity: quantity.value));
  }

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
              if (_searching)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16),
                  child: CatalogSearchList(snapshot: snap, onPick: _link),
                ),
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
}
