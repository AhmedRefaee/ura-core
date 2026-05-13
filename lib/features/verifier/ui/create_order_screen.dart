import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../logic/create_order_cubit.dart';
import '../../inventory/ui/inventory_item_detail_screen.dart';
import 'widgets/add_item_sheet.dart';
import 'widgets/templates_sheet.dart';
import '../../../core/design_system/theme/theme.dart';

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
        if (state is CreateOrderReady && state.templateSaveSucceeded) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ القالب بنجاح')),
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
                  SizedBox(height: AppSpacing.verticalMedium),
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
          appBar: AppBar(
            title: const Text('طلب جديد'),
            actions: [
              if (ready != null && ready.canSubmit)
                IconButton(
                  tooltip: 'حفظ كقالب',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () =>
                      context.read<CreateOrderCubit>().saveAsTemplate(),
                ),
            ],
          ),
          body: ready == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: AppSpacing.allLarge,
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
                      SizedBox(height: AppSpacing.verticalXLarge),

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
                      SizedBox(height: AppSpacing.verticalXLarge),

                      // Rep (not for inbound_external)
                      if (ready.direction != OrderDirection.inboundExternal) ...[
                        _SectionTitle('المندوب'),
                        _RepPicker(
                          reps: ready.reps,
                          selected: ready.selectedRep,
                          onChanged: (r) =>
                              context.read<CreateOrderCubit>().selectRep(r),
                        ),
                        SizedBox(height: AppSpacing.verticalXLarge),
                      ],

                      // Items
                      Row(
                        children: [
                          _SectionTitle('الأصناف'),
                          const Spacer(),
                          if (ready.selectedEntity != null)
                            TextButton.icon(
                              onPressed: () => _showTemplatesSheet(context, ready),
                              icon: const Icon(Icons.flash_on, size: 18),
                              label: const Text('قالب'),
                            ),
                          TextButton.icon(
                            onPressed: () => _showAddItemDialog(context, ready),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      _OrderItemsList(
                        items: ready.items,
                        inventory: ready.inventory,
                        direction: ready.direction,
                      ),
                      SizedBox(height: AppSpacing.verticalXLarge),

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
                      SizedBox(height: AppSpacing.verticalXXXLarge),

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
    final inventory = state.direction == OrderDirection.outbound
        ? _applyDraftReservations(state.inventory, state.items)
        : state.inventory;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemSheet(
          inventory: inventory,
          orderDirection: state.direction,
          onAddInventoryItems: (items) => cubit.addMultipleItems(items),
          onAddCustomItem: (desc, qty, {sourceInventoryId}) =>
              cubit.addCustomItem(desc, qty, sourceInventoryId: sourceInventoryId),
        ),
      ),
    );
  }

  List<InventoryItem> _applyDraftReservations(
    List<InventoryItem> inventory,
    List<DraftOrderItem> draftItems,
  ) {
    final Map<String, int> reserved = {};
    for (final item in draftItems) {
      if (item.inventoryId != null) {
        reserved[item.inventoryId!] = (reserved[item.inventoryId!] ?? 0) + item.quantity;
      }
    }
    if (reserved.isEmpty) return inventory;
    return inventory.map((inv) {
      final r = reserved[inv.id] ?? 0;
      if (r == 0) return inv;
      return InventoryItem(
        id: inv.id,
        itemName: inv.itemName,
        sku: inv.sku,
        quantity: (inv.quantity - r).clamp(0, inv.quantity),
        unit: inv.unit,
        category: inv.category,
        minQuantity: inv.minQuantity,
        description: inv.description,
      );
    }).toList();
  }

  void _showTemplatesSheet(BuildContext context, CreateOrderReady state) {
    final cubit = context.read<CreateOrderCubit>();
    showTemplatesSheet(
      context: context,
      entityId: state.selectedEntity!.id,
      entityName: state.selectedEntity!.name,
      onApply: (template) => cubit.applyTemplate(template),
    );
  }
}

class _OrderItemsList extends StatelessWidget {
  final List<DraftOrderItem> items;
  final List<InventoryItem> inventory;
  final OrderDirection direction;

  const _OrderItemsList({
    required this.items,
    required this.inventory,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('لم يتم إضافة أصناف بعد', style: TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < items.length; i++)
          _buildItemTile(context, i, items[i]),
      ],
    );
  }

  Widget _buildItemTile(BuildContext context, int index, DraftOrderItem item) {
    final invItem = direction == OrderDirection.outbound && item.inventoryId != null
        ? inventory.where((inv) => inv.id == item.inventoryId).firstOrNull
        : null;
    final isOverStock = invItem != null && item.quantity > invItem.quantity;

    return ListTile(
      dense: true,
      title: Text(item.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('الكمية: ${item.quantity}'),
          if (isOverStock)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventoryItemDetailScreen(item: invItem),
                ),
              ),
              child: Chip(
                avatar: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                label: Text(
                  'المتوفر فقط: ${invItem.quantity}',
                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                ),
                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: () => context.read<CreateOrderCubit>().removeItem(index),
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
      padding: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
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
        ButtonSegment(
            value: OrderDirection.inboundExternal, label: Text('وارد (خارجي)')),
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showEntitySheet(context, entities),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalMedium, vertical: AppSpacing.verticalLarge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.name ?? 'اختر...',
                style: TextStyle(
                  color: selected != null ? null : theme.hintColor,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }

  void _showEntitySheet(BuildContext context, List<Entity> entities) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _EntitySheet(
        entities: entities,
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
  EntityCategory? _categoryFilter;
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
    _applyFilters();
  }

  void _onCategoryFilterChanged(EntityCategory? category) {
    setState(() {
      _categoryFilter = category;
    });
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.entities.where((entity) {
        // Filter by category
        if (_categoryFilter != null && entity.category != _categoryFilter) {
          return false;
        }
        // Filter by search query
        if (query.isNotEmpty && !entity.name.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: AppSpacing.verticalSmall),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: AppSpacing.allLarge,
              child: Text(
                widget.selected == null ? 'اختر جهة' : 'تغيير الجهة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.horizontalLargePadding,
              child: TextFormField(
                controller: _searchController,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الجهة...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor ?? theme.scaffoldBackgroundColor,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.verticalMedium),
            _FilterChips(
              selectedFilter: _categoryFilter,
              onChanged: _onCategoryFilterChanged,
            ),
            SizedBox(height: AppSpacing.verticalSmall),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('لا توجد نتائج'))
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
                          selectedTileColor: Colors.green.withValues(alpha: 0.1),
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

class _FilterChips extends StatelessWidget {
  final EntityCategory? selectedFilter;
  final ValueChanged<EntityCategory?> onChanged;

  const _FilterChips({
    required this.selectedFilter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: AppSpacing.horizontalLargePadding,
      child: Row(
        children: [
          _FilterChip(
            label: 'الكل',
            isSelected: selectedFilter == null,
            onTap: () => onChanged(null),
          ),
          SizedBox(width: AppSpacing.horizontalSmall),
          _FilterChip(
            label: 'وارد',
            isSelected: selectedFilter == EntityCategory.incoming,
            onTap: () => onChanged(EntityCategory.incoming),
          ),
          SizedBox(width: AppSpacing.horizontalSmall),
          _FilterChip(
            label: 'صادر',
            isSelected: selectedFilter == EntityCategory.outgoing,
            onTap: () => onChanged(EntityCategory.outgoing),
          ),
          SizedBox(width: AppSpacing.horizontalSmall),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: theme.colorScheme.surface,
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
      ),
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalMedium, vertical: AppSpacing.verticalSmall),
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showRepSheet(context, reps),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalMedium, vertical: AppSpacing.verticalLarge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.fullName ?? 'اختر مندوباً...',
                style: TextStyle(
                  color: selected != null ? null : theme.hintColor,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
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
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: AppSpacing.verticalSmall),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: AppSpacing.allLarge,
              child: Text(
                widget.selected == null ? 'اختر مندوباً' : 'تغيير المندوب',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.horizontalLargePadding,
              child: TextFormField(
                controller: _searchController,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المندوب...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor ?? theme.scaffoldBackgroundColor,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.verticalMedium),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('لا توجد نتائج'))
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
                          selectedTileColor: Colors.green.withValues(alpha: 0.1),
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
