import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_bulk_cubit.dart';

class InventoryBulkEditScreen extends StatelessWidget {
  const InventoryBulkEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<InventoryBulkCubit>()..loadItems(),
      child: const _InventoryBulkEditView(),
    );
  }
}

class _InventoryBulkEditView extends StatelessWidget {
  const _InventoryBulkEditView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InventoryBulkCubit, InventoryBulkState>(
      listener: (context, state) {
        if (state is InventoryBulkSuccess) {
          Navigator.pop(context, true);
        }
        if (state is InventoryBulkError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('تعديل الكميات'),
            actions: [
              if (state is InventoryBulkReady && state.hasChanges)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: Text(
                      '${state.pendingQuantities.length} تغيير',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: () {
            if (state is InventoryBulkLoading ||
                state is InventoryBulkInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is InventoryBulkSaving) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('جاري الحفظ...'),
                  ],
                ),
              );
            }
            if (state is InventoryBulkError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message,
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          context.read<InventoryBulkCubit>().loadItems(),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              );
            }
            if (state is InventoryBulkReady) {
              if (state.items.isEmpty) {
                return const Center(child: Text('لا توجد عناصر في المخزون'));
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: state.items.length,
                itemBuilder: (_, i) =>
                    _BulkItemRow(item: state.items[i], state: state),
              );
            }
            return const SizedBox.shrink();
          }(),
          bottomNavigationBar: state is InventoryBulkReady
              ? _BottomBar(state: state)
              : null,
        );
      },
    );
  }
}

class _BulkItemRow extends StatefulWidget {
  final InventoryItem item;
  final InventoryBulkReady state;

  const _BulkItemRow({required this.item, required this.state});

  @override
  State<_BulkItemRow> createState() => _BulkItemRowState();
}

class _BulkItemRowState extends State<_BulkItemRow> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: '${widget.state.effectiveQuantity(widget.item)}',
    );
  }

  @override
  void didUpdateWidget(_BulkItemRow old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      final newVal = '${widget.state.effectiveQuantity(widget.item)}';
      if (_ctrl.text != newVal) _ctrl.text = newVal;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChanged =
        widget.state.pendingQuantities.containsKey(widget.item.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isChanged
          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(60)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.itemName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (widget.item.category != null)
                    Text(
                      widget.item.category!,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (isChanged)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '(أصلي: ${widget.item.quantity})',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: isChanged
                        ? BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2)
                        : const BorderSide(),
                  ),
                  suffixText: widget.item.unit,
                ),
                onTap: () => setState(() => _editing = true),
                onChanged: (_) => setState(() {}),
                onSubmitted: _commit,
                onEditingComplete: () => _commit(_ctrl.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commit(String value) {
    setState(() => _editing = false);
    final qty = int.tryParse(value.trim());
    if (qty != null && qty >= 0) {
      context.read<InventoryBulkCubit>().setQuantity(widget.item.id, qty);
    } else {
      // revert to current effective quantity
      _ctrl.text = '${widget.state.effectiveQuantity(widget.item)}';
    }
  }
}

class _BottomBar extends StatelessWidget {
  final InventoryBulkReady state;
  const _BottomBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: state.hasChanges
              ? () => context.read<InventoryBulkCubit>().saveChanges()
              : null,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            state.hasChanges
                ? 'حفظ ${state.pendingQuantities.length} تغيير'
                : 'لا توجد تغييرات',
          ),
        ),
      ),
    );
  }
}
