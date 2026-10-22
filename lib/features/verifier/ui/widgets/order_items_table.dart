import 'package:flutter/material.dart';
import '../../../../shared/models/draft_order_item.dart';
import '../../../../shared/utils/quantity_format.dart';
import '../../data/local_item_matcher.dart';

typedef TypedLine = ({String name, String unit, double quantity});

/// An order's items as one editable table (الصنف / الوحدة / الكمية): the
/// verifier types a line with "إضافة صنف" or pastes a whole list, and edits
/// any row in place. What is written here *is* the order -- there is no
/// separate draft to move across, so nothing typed can be left behind.
///
/// Nothing is matched against the catalog. Whether storage has an item, and
/// which catalog row it is, is storage's call when it reviews the order.
/// Catalog rows (from a template, a copied order, or the restock picker)
/// show their name read-only; only their quantity is editable.
class OrderItemsTable extends StatefulWidget {
  final List<DraftOrderItem> items;
  final ValueChanged<List<TypedLine>> onAddTyped;
  final void Function(int index, {String? name, String? unit, double? quantity}) onEditTyped;
  final void Function(int index, double quantity) onQuantityChanged;
  final ValueChanged<int> onRemove;

  /// Opens a typed line's full details (brand, variety, packaging...).
  final ValueChanged<int>? onEditDetails;

  /// Extra buttons beside "إضافة صنف" / "لصق قائمة" -- the restock picker.
  final List<Widget> extraActions;

  const OrderItemsTable({
    super.key,
    required this.items,
    required this.onAddTyped,
    required this.onEditTyped,
    required this.onQuantityChanged,
    required this.onRemove,
    this.onEditDetails,
    this.extraActions = const [],
  });

  /// Below this width a row's name gets a line of its own.
  static const narrowWidth = 420.0;

  @override
  State<OrderItemsTable> createState() => _OrderItemsTableState();
}

class _OrderItemsTableState extends State<OrderItemsTable> {
  /// Set when "إضافة صنف" adds a row, so that row's name field takes focus.
  int? _focusAfterLength;

  void _addEmpty() {
    _focusAfterLength = widget.items.length;
    widget.onAddTyped(const [(name: '', unit: '', quantity: 1)]);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final focusLast = _focusAfterLength != null && items.length > _focusAfterLength!;
    if (focusLast) _focusAfterLength = null;
    final incomplete = items.where((i) => !i.isComplete).length;

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < OrderItemsTable.narrowWidth;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'لا توجد أصناف بعد — أضف صنفاً أو الصق قائمة',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          else if (!narrow)
            const _HeaderRow(),
          for (var i = 0; i < items.length; i++)
            _ItemRow(
              key: ValueKey(items[i].rowKey ?? 'i$i'),
              item: items[i],
              index: i,
              narrow: narrow,
              autofocus: focusLast && i == items.length - 1,
              table: widget,
            ),
          if (incomplete > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                incomplete == 1
                    ? 'صنف واحد ينقصه الاسم أو الكمية'
                    : '$incomplete أصناف ينقصها الاسم أو الكمية',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          const SizedBox(height: 8),
          // Wrap, not a Row: buttons must not overflow a narrow phone, and a
          // horizontal strip can't be dragged with a mouse.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _addEmpty,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة صنف'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showPasteDialog(context),
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('لصق قائمة'),
              ),
              ...widget.extraActions,
            ],
          ),
        ],
      );
    });
  }

  Future<void> _showPasteDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    final lines = [
      for (final p in LocalItemMatcher.parseRequest(text))
        (name: p.name, unit: p.unit ?? '', quantity: p.quantity),
    ];
    widget.onAddTyped(lines);
    messenger.showSnackBar(SnackBar(
      content: Text(lines.isEmpty
          ? 'لم يتم التعرف على أصناف في النص'
          : 'تمت إضافة ${lines.length} صنف — راجعها وعدّل ما يلزم'),
    ));
  }
}

/// Owns its controller: the dialog is still animating out after it pops, so
/// the caller must not dispose a controller it is still drawing.
class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('لصق قائمة الأصناف'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'الصق رسالة الطلب هنا، سطر لكل صنف...',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('إضافة الأصناف'),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600);
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text('الصنف', style: style)),
          SizedBox(width: 8),
          SizedBox(width: 90, child: Text('الوحدة', style: style)),
          SizedBox(width: 8),
          SizedBox(width: 70, child: Text('الكمية', style: style)),
          SizedBox(width: 80),
        ],
      ),
    );
  }
}

InputDecoration _cell({String? hint, bool error = false}) => InputDecoration(
      isDense: true,
      hintText: hint,
      border: const OutlineInputBorder(),
      enabledBorder: error
          ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.red))
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );

class _ItemRow extends StatefulWidget {
  final DraftOrderItem item;
  final int index;
  final bool narrow;
  final bool autofocus;
  final OrderItemsTable table;

  const _ItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.narrow,
    required this.autofocus,
    required this.table,
  });

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final _name = TextEditingController(text: widget.item.typedName);
  late final _unit = TextEditingController(text: widget.item.typedUnit);
  late final _qty = TextEditingController(
    text: widget.item.quantity > 0 ? formatQty(widget.item.quantity) : '',
  );
  final _nameFocus = FocusNode();
  final _unitFocus = FocusNode();
  final _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // A just-added empty row is not an error yet -- only once the verifier
    // has left its name field without writing anything.
    _nameFocus.addListener(() => setState(() {}));
  }

  /// The details sheet can rewrite a line from outside; show what it now
  /// says. A field being typed into is the source of the change, so it is
  /// left alone.
  @override
  void didUpdateWidget(_ItemRow old) {
    super.didUpdateWidget(old);
    final item = widget.item;
    if (!_nameFocus.hasFocus && item.typedName != _name.text) _name.text = item.typedName;
    if (!_unitFocus.hasFocus && item.typedUnit != old.item.typedUnit) _unit.text = item.typedUnit;
    if (!_qtyFocus.hasFocus && item.quantity != old.item.quantity) {
      _qty.text = item.quantity > 0 ? formatQty(item.quantity) : '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _qty.dispose();
    _nameFocus.dispose();
    _unitFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final t = widget.table;
    final i = widget.index;

    final Widget name = item.isCustom
        ? TextField(
            controller: _name,
            focusNode: _nameFocus,
            autofocus: widget.autofocus,
            decoration: _cell(
              hint: 'اسم الصنف',
              error: item.typedName.trim().isEmpty && !_nameFocus.hasFocus,
            ),
            onChanged: (v) => t.onEditTyped(i, name: v),
          )
        : Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          );

    final Widget unit = SizedBox(
      width: 90,
      child: item.isCustom
          ? TextField(
              controller: _unit,
              focusNode: _unitFocus,
              decoration: _cell(hint: 'قطعة'),
              onChanged: (v) => t.onEditTyped(i, unit: v),
            )
          : const SizedBox.shrink(),
    );

    final Widget qty = SizedBox(
      width: 70,
      child: TextField(
        controller: _qty,
        focusNode: _qtyFocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [quantityInputFormatter],
        textAlign: TextAlign.center,
        decoration: _cell(hint: '1', error: item.quantity <= 0),
        onChanged: (v) {
          final q = double.tryParse(v.replaceAll(',', '.')) ?? 0;
          item.isCustom ? t.onEditTyped(i, quantity: q) : t.onQuantityChanged(i, q);
        },
      ),
    );

    final Widget actions = SizedBox(
      width: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (item.isCustom && t.onEditDetails != null)
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'تفاصيل الصنف',
              visualDensity: VisualDensity.compact,
              onPressed: () => t.onEditDetails!(i),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            tooltip: 'حذف',
            visualDensity: VisualDensity.compact,
            onPressed: () => t.onRemove(i),
          ),
        ],
      ),
    );

    if (widget.narrow) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.25))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            name,
            const SizedBox(height: 6),
            Row(children: [unit, const SizedBox(width: 8), qty, const Spacer(), actions]),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: name),
          const SizedBox(width: 8),
          unit,
          const SizedBox(width: 8),
          qty,
          actions,
        ],
      ),
    );
  }
}
