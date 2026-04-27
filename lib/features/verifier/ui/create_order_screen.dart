import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../logic/create_order_cubit.dart';
import 'widgets/add_item_sheet.dart';

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
    final cubit = context.read<CreateOrderCubit>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemSheet(
          inventory: state.inventory,
          orderDirection: state.direction,
          onAddInventoryItems: (items) => cubit.addMultipleItems(items),
          onAddCustomItem: (desc, qty, {sourceInventoryId}) =>
              cubit.addCustomItem(desc, qty, sourceInventoryId: sourceInventoryId),
        ),
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

    return InkWell(
      onTap: () => _showEntitySheet(context, filtered),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.name ?? 'اختر...',
                style: TextStyle(
                  color: selected != null ? null : Colors.grey[600],
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  void _showEntitySheet(BuildContext context, List<Entity> filteredEntities) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _EntitySheet(
        entities: filteredEntities,
        selected: selected,
        onSelected: (entity) {
          onChanged(entity);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }
}

class _EntitySheet extends StatefulWidget {
  final List<Entity> entities;
  final Entity? selected;
  final ValueChanged<Entity> onSelected;

  const _EntitySheet({
    required this.entities,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_EntitySheet> createState() => _EntitySheetState();
}

class _EntitySheetState extends State<_EntitySheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Entity> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.entities;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.entities
          .where((e) => e.name.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.selected == null ? 'اختر جهة' : 'تغيير الجهة',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الجهة...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Entity list
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text('لا توجد نتائج'),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final entity = _filtered[index];
                        final isSelected = widget.selected?.id == entity.id;
                        return ListTile(
                          title: Text(entity.name),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          selected: isSelected,
                          selectedTileColor: Colors.green.withOpacity(0.1),
                          onTap: () => widget.onSelected(entity),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
    return InkWell(
      onTap: () => _showRepSheet(context, reps),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.fullName ?? 'اختر مندوباً...',
                style: TextStyle(
                  color: selected != null ? null : Colors.grey[600],
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  void _showRepSheet(BuildContext context, List<Profile> allReps) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RepSheet(
        reps: allReps,
        selected: selected,
        onSelected: (rep) {
          onChanged(rep);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }
}

class _RepSheet extends StatefulWidget {
  final List<Profile> reps;
  final Profile? selected;
  final ValueChanged<Profile> onSelected;

  const _RepSheet({
    required this.reps,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_RepSheet> createState() => _RepSheetState();
}

class _RepSheetState extends State<_RepSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Profile> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.reps;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.reps
          .where((r) => r.fullName.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.selected == null ? 'اختر مندوباً' : 'تغيير المندوب',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المندوب...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Rep list
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text('لا توجد نتائج'),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final rep = _filtered[index];
                        final isSelected = widget.selected?.id == rep.id;
                        return ListTile(
                          title: Text(rep.fullName),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          selected: isSelected,
                          selectedTileColor: Colors.green.withOpacity(0.1),
                          onTap: () => widget.onSelected(rep),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

