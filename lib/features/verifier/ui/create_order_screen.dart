import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../logic/create_order_cubit.dart';

class CreateOrderScreen extends StatelessWidget {
  const CreateOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CreateOrderCubit, CreateOrderState>(
      listener: (context, state) {
        if (state is CreateOrderSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إنشاء الطلب بنجاح')),
          );
          Navigator.pop(context, true);
        }
        if (state is CreateOrderError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is CreateOrderInitial || state is CreateOrderLoadingLookups) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is CreateOrderError && state is! CreateOrderReady) {
          return Scaffold(
            appBar: AppBar(title: const Text('طلب جديد')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () =>
                        context.read<CreateOrderCubit>().loadLookups(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final ready = state is CreateOrderReady ? state : null;
        final isSubmitting = state is CreateOrderSubmitting;

        return Scaffold(
          appBar: AppBar(title: const Text('طلب جديد')),
          body: ready == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Direction
                      _SectionTitle('اتجاه الطلب'),
                      _DirectionSelector(
                        selected: ready.direction,
                        onChanged: (d) =>
                            context.read<CreateOrderCubit>().setDirection(d),
                      ),
                      const SizedBox(height: 20),

                      // Entity
                      _SectionTitle(ready.direction == OrderDirection.outbound
                          ? 'العميل'
                          : 'المورد'),
                      _EntityPicker(
                        entities: ready.entities,
                        selected: ready.selectedEntity,
                        direction: ready.direction,
                        onChanged: (e) =>
                            context.read<CreateOrderCubit>().selectEntity(e),
                      ),
                      const SizedBox(height: 20),

                      // Rep (not for inbound_external)
                      if (ready.direction != OrderDirection.inboundExternal) ...[
                        _SectionTitle('المندوب'),
                        _RepPicker(
                          reps: ready.reps,
                          selected: ready.selectedRep,
                          onChanged: (r) =>
                              context.read<CreateOrderCubit>().selectRep(r),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Items
                      Row(
                        children: [
                          _SectionTitle('الأصناف'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showAddItemDialog(context, ready),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      if (ready.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('لم يتم إضافة أصناف بعد',
                              style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...ready.items.asMap().entries.map((e) => ListTile(
                              dense: true,
                              title: Text(e.value.displayName),
                              subtitle: Text('الكمية: ${e.value.quantity}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => context
                                    .read<CreateOrderCubit>()
                                    .removeItem(e.key),
                              ),
                            )),
                      const SizedBox(height: 20),

                      // Notes
                      _SectionTitle('ملاحظات (اختياري)'),
                      TextField(
                        maxLines: 2,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'أي تعليمات أو ملاحظات...',
                        ),
                        onChanged: (v) =>
                            context.read<CreateOrderCubit>().setNotes(v),
                      ),
                      const SizedBox(height: 32),

                      FilledButton(
                        onPressed: isSubmitting || !ready.canSubmit
                            ? null
                            : () => context.read<CreateOrderCubit>().submit(),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('إنشاء الطلب'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _showAddItemDialog(BuildContext context, CreateOrderReady state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<CreateOrderCubit>(),
        child: _AddItemSheet(inventory: state.inventory),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class _DirectionSelector extends StatelessWidget {
  final OrderDirection selected;
  final ValueChanged<OrderDirection> onChanged;
  const _DirectionSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<OrderDirection>(
      segments: const [
        ButtonSegment(value: OrderDirection.outbound, label: Text('صادر')),
        ButtonSegment(value: OrderDirection.inboundRep, label: Text('وارد (مندوب)')),
        ButtonSegment(value: OrderDirection.inboundExternal, label: Text('وارد (خارجي)')),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _EntityPicker extends StatelessWidget {
  final List<Entity> entities;
  final Entity? selected;
  final OrderDirection direction;
  final ValueChanged<Entity> onChanged;

  const _EntityPicker({
    required this.entities,
    required this.selected,
    required this.direction,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = direction == OrderDirection.outbound
        ? entities.where((e) => e.type == EntityType.customer).toList()
        : entities.where((e) => e.type == EntityType.supplier).toList();

    return DropdownButtonFormField<Entity>(
      value: selected,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      hint: const Text('اختر...'),
      items: filtered
          .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
          .toList(),
      onChanged: (e) {
        if (e != null) onChanged(e);
      },
    );
  }
}

class _RepPicker extends StatelessWidget {
  final List<Profile> reps;
  final Profile? selected;
  final ValueChanged<Profile> onChanged;

  const _RepPicker({
    required this.reps,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Profile>(
      value: selected,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      hint: const Text('اختر مندوباً...'),
      items: reps
          .map((r) => DropdownMenuItem(value: r, child: Text(r.fullName)))
          .toList(),
      onChanged: (r) {
        if (r != null) onChanged(r);
      },
    );
  }
}

class _AddItemSheet extends StatefulWidget {
  final List<InventoryItem> inventory;
  const _AddItemSheet({required this.inventory});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  bool _isCustom = false;
  InventoryItem? _selectedItem;
  final _quantityController = TextEditingController(text: '1');
  final _descController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _quantityController.dispose();
    _descController.dispose();
    super.dispose();
  }

  List<InventoryItem> get _filtered => widget.inventory
      .where((i) => i.itemName.contains(_search))
      .toList();

  void _submit() {
    final qty = int.tryParse(_quantityController.text) ?? 0;
    if (qty <= 0) return;
    if (_isCustom) {
      final desc = _descController.text.trim();
      if (desc.isEmpty) return;
      context.read<CreateOrderCubit>().addCustomItem(desc, qty);
    } else {
      if (_selectedItem == null) return;
      context.read<CreateOrderCubit>().addInventoryItem(_selectedItem!, qty);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('إضافة صنف',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              Switch(
                value: _isCustom,
                onChanged: (v) => setState(() => _isCustom = v),
              ),
              const Text('مخصص'),
            ],
          ),
          const SizedBox(height: 12),
          if (_isCustom) ...[
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'وصف الصنف',
                border: OutlineInputBorder(),
              ),
            ),
          ] else ...[
            TextField(
              decoration: const InputDecoration(
                labelText: 'بحث',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final item = _filtered[i];
                  return RadioListTile<InventoryItem>(
                    title: Text(item.itemName),
                    subtitle: Text('المتوفر: ${item.quantity} ${item.unit}'),
                    value: item,
                    groupValue: _selectedItem,
                    onChanged: (v) => setState(() => _selectedItem = v),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'الكمية',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('إضافة')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
