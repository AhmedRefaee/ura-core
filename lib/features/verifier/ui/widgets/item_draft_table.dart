import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/utils/quantity_format.dart';
import '../../logic/item_draft_cubit.dart';

/// Where the verifier writes an order's items: one row per item (الصنف /
/// الوحدة / الكمية), typed with ➕ or filled from a pasted list. Optionally
/// checked against the catalog, then handed to the order with
/// "إضافة إلى الطلب" -- nothing here is part of the order until then.
///
/// Expects an [ItemDraftCubit] above it.
class ItemDraftTable extends StatelessWidget {
  final List<InventoryItem> inventory;

  /// Receives the complete rows; incomplete ones stay in the draft.
  final ValueChanged<List<DraftRow>> onCommit;

  const ItemDraftTable({super.key, required this.inventory, required this.onCommit});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ItemDraftCubit, ItemDraftState>(
      listenWhen: (a, b) => b.notice != null && a.notice != b.notice,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.notice!)));
        context.read<ItemDraftCubit>().clearNotice();
      },
      builder: (context, state) {
        final cubit = context.read<ItemDraftCubit>();
        final hasNamed = state.rows.any((r) => r.name.trim().isNotEmpty);
        final hasValid = state.rows.any((r) => r.isValid);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'مسودة الأصناف',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const _HeaderRow(),
                for (final row in state.rows)
                  _DraftRowTile(key: ValueKey(row.id), row: row),
                const _EntryRow(),
                const SizedBox(height: 8),
                // Wrap, not a Row: on a narrow phone the two buttons must not
                // overflow, and a horizontal strip can't be dragged with a mouse.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showPasteDialog(context),
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('لصق قائمة'),
                    ),
                    OutlinedButton.icon(
                      onPressed: hasNamed && !state.matching
                          ? () => cubit.checkMatches(inventory)
                          : null,
                      icon: state.matching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.manage_search, size: 18),
                      label: const Text('مطابقة مع المخزن'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: hasValid && !state.matching
                      ? () => onCommit(cubit.takeValidRows())
                      : null,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('إضافة إلى الطلب'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPasteDialog(BuildContext context) async {
    final cubit = context.read<ItemDraftCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('لصق قائمة الأصناف'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('تعبئة المسودة'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final added = cubit.appendPasted(text);
    messenger.showSnackBar(SnackBar(
      content: Text(added == 0
          ? 'لم يتم التعرف على أصناف في النص'
          : 'تمت إضافة $added صنف للمسودة — راجعها قبل الإضافة للطلب'),
    ));
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
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

InputDecoration _cellDecoration({String? hint, bool error = false}) => InputDecoration(
      isDense: true,
      hintText: hint,
      border: const OutlineInputBorder(),
      enabledBorder: error
          ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.red))
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );

/// A row already in the draft: editable in place, with its catalog
/// suggestions underneath once matching has run.
class _DraftRowTile extends StatefulWidget {
  final DraftRow row;
  const _DraftRowTile({super.key, required this.row});

  @override
  State<_DraftRowTile> createState() => _DraftRowTileState();
}

class _DraftRowTileState extends State<_DraftRowTile> {
  late final _name = TextEditingController(text: widget.row.name);
  late final _unit = TextEditingController(text: widget.row.unit);
  late final _qty = TextEditingController(text: widget.row.quantityText);

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ItemDraftCubit>();
    final row = widget.row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: _cellDecoration(error: row.name.trim().isEmpty),
                  onChanged: (v) => cubit.updateRow(row.id, name: v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _unit,
                  decoration: _cellDecoration(hint: 'قطعة'),
                  onChanged: (v) => cubit.updateRow(row.id, unit: v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [quantityInputFormatter],
                  textAlign: TextAlign.center,
                  decoration: _cellDecoration(error: (row.quantity ?? 0) <= 0),
                  onChanged: (v) => cubit.updateRow(row.id, quantityText: v),
                ),
              ),
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'حذف',
                  onPressed: () => cubit.removeRow(row.id),
                ),
              ),
            ],
          ),
          if (row.suggestions.isNotEmpty) _Suggestions(row: row),
        ],
      ),
    );
  }
}

/// The catalog rows matching offered for one line, plus "keep as typed".
/// Wrap, never a horizontal strip -- a mouse cannot drag one.
class _Suggestions extends StatelessWidget {
  final DraftRow row;
  const _Suggestions({required this.row});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ItemDraftCubit>();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('في المخزن:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ChoiceChip(
            label: const Text('كما كتبته'),
            selected: row.chosen == null,
            onSelected: (_) => cubit.choose(row.id, null),
            visualDensity: VisualDensity.compact,
          ),
          for (final item in row.suggestions)
            ChoiceChip(
              avatar: const Icon(Icons.inventory_2_outlined, size: 16),
              label: Text(item.itemName),
              selected: row.chosen?.id == item.id,
              onSelected: (_) => cubit.choose(row.id, item),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// The empty row at the bottom: fill it, tap ➕, and it joins the draft.
class _EntryRow extends StatefulWidget {
  const _EntryRow();

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _qty = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _qty.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _add() {
    if (_name.text.trim().isEmpty) {
      _nameFocus.requestFocus();
      return;
    }
    context.read<ItemDraftCubit>().addRow(
          name: _name.text.trim(),
          unit: _unit.text.trim(),
          quantityText: _qty.text.trim().isEmpty ? '1' : _qty.text.trim(),
        );
    _name.clear();
    _unit.clear();
    _qty.clear();
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.verticalXSmall),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('draft-entry-name'),
              controller: _name,
              focusNode: _nameFocus,
              decoration: _cellDecoration(hint: 'اسم الصنف'),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              key: const ValueKey('draft-entry-unit'),
              controller: _unit,
              decoration: _cellDecoration(hint: 'الوحدة'),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              key: const ValueKey('draft-entry-qty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [quantityInputFormatter],
              textAlign: TextAlign.center,
              decoration: _cellDecoration(hint: '1'),
              onSubmitted: (_) => _add(),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.teal),
              tooltip: 'إضافة صف',
              onPressed: _add,
            ),
          ),
        ],
      ),
    );
  }
}
