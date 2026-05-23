import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_list_cubit.dart';
import 'inventory_bulk_edit_screen.dart';
import 'inventory_form_screen.dart';
import 'inventory_item_detail_screen.dart';
import '../logic/bulk_edit_excel_cubit.dart';
import '../logic/import_items_cubit.dart';
import 'bulk_edit_excel_screen.dart';
import 'import_items_screen.dart';
import 'widgets/inventory_item_card.dart';

enum _ExcelAction { importNew, bulkEdit }

enum _InventoryViewMode { list, grid }

enum _InventorySortMode { name, mostUsed, highestQuantity, lowStockFirst }

extension _InventoryViewModeLabel on _InventoryViewMode {
  String get label => switch (this) {
    _InventoryViewMode.list => 'قائمة',
    _InventoryViewMode.grid => 'شبكة',
  };

  IconData get icon => switch (this) {
    _InventoryViewMode.list => Icons.view_list_outlined,
    _InventoryViewMode.grid => Icons.grid_view_outlined,
  };
}

extension _InventorySortModeLabel on _InventorySortMode {
  String get label => switch (this) {
    _InventorySortMode.name => 'الاسم',
    _InventorySortMode.mostUsed => 'الأكثر استخداماً',
    _InventorySortMode.highestQuantity => 'الأعلى كمية',
    _InventorySortMode.lowStockFirst => 'الأولوية للمنخفض',
  };
}

class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<InventoryListCubit>()..loadInventory(),
      child: const _InventoryManagementView(),
    );
  }
}

class _InventoryManagementView extends StatefulWidget {
  const _InventoryManagementView();

  @override
  State<_InventoryManagementView> createState() =>
      _InventoryManagementViewState();
}

class _InventoryManagementViewState extends State<_InventoryManagementView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('إدارة المخزون'),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'إضافة صنف',
          onPressed: () => _openCreate(context),
        ),
        PopupMenuButton<_ExcelAction>(
          icon: const Icon(Icons.table_chart_outlined),
          tooltip: 'خيارات Excel',
          onSelected: (action) {
            if (action == _ExcelAction.importNew) _openImport(context);
            if (action == _ExcelAction.bulkEdit) _openBulkEditExcel(context);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _ExcelAction.importNew,
              child: ListTile(
                leading: Icon(Icons.upload_file_outlined),
                title: Text('استيراد عناصر جديدة'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _ExcelAction.bulkEdit,
              child: ListTile(
                leading: Icon(Icons.sync_alt_outlined),
                title: Text('تعديل جماعي عبر Excel'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.edit_note_outlined),
          tooltip: 'تعديل الكميات',
          onPressed: () => _openBulkEdit(context),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
          onPressed: () {
            _searchController.clear();
            context.read<InventoryListCubit>().loadInventory();
          },
        ),
      ],
      body: BlocBuilder<InventoryListCubit, InventoryListState>(
        builder: (context, state) {
          if (state is InventoryListLoading || state is InventoryListInitial) {
            return Builder(
              builder: (ctx) => const CollapsingInnerScrollBody(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: AppLoadingIndicator()),
                  ),
                ],
              ),
            );
          }
          if (state is InventoryListError) {
            return Builder(
              builder: (ctx) => CollapsingInnerScrollBody(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            state.message,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                          SizedBox(height: AppSpacing.verticalMedium),
                          AppButton(
                            onPressed: () => context
                                .read<InventoryListCubit>()
                                .loadInventory(),
                            text: 'إعادة المحاولة',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          if (state is InventoryListLoaded) {
            return _LoadedView(
              state: state,
              searchController: _searchController,
              onTap: (item) => _openDetail(context, item),
              onCreate: () => _openCreate(context),
              onBulkEdit: () => _openBulkEdit(context),
              onImport: () => _openImport(context),
              onBulkEditExcel: () => _openBulkEditExcel(context),
            );
          }
          return Builder(
            builder: (ctx) => const CollapsingInnerScrollBody(
              slivers: [SliverFillRemaining(child: SizedBox.shrink())],
            ),
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, InventoryItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InventoryItemDetailScreen(item: item)),
    );
    if (context.mounted) {
      context.read<InventoryListCubit>().loadInventory();
    }
  }

  void _openCreate(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const InventoryFormScreen()),
    );
    if (created == true && context.mounted) {
      context.read<InventoryListCubit>().loadInventory();
    }
  }

  void _openImport(BuildContext context) async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<ImportItemsCubit>(),
          child: const ImportItemsScreen(),
        ),
      ),
    );
    if (imported == true && context.mounted) {
      context.read<InventoryListCubit>().loadInventory();
    }
  }

  void _openBulkEditExcel(BuildContext context) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<BulkEditExcelCubit>(),
          child: const BulkEditExcelScreen(),
        ),
      ),
    );
    if (updated == true && context.mounted) {
      context.read<InventoryListCubit>().loadInventory();
    }
  }

  void _openBulkEdit(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const InventoryBulkEditScreen()),
    );
    if (saved == true && context.mounted) {
      context.read<InventoryListCubit>().loadInventory();
    }
  }
}

class _LoadedView extends StatefulWidget {
  final InventoryListLoaded state;
  final TextEditingController searchController;
  final void Function(InventoryItem) onTap;
  final VoidCallback onCreate;
  final VoidCallback onBulkEdit;
  final VoidCallback onImport;
  final VoidCallback onBulkEditExcel;

  const _LoadedView({
    required this.state,
    required this.searchController,
    required this.onTap,
    required this.onCreate,
    required this.onBulkEdit,
    required this.onImport,
    required this.onBulkEditExcel,
  });

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  bool _filtersVisible = false;
  _InventoryViewMode _viewMode = _InventoryViewMode.list;
  _InventorySortMode _sortMode = _InventorySortMode.name;

  @override
  Widget build(BuildContext context) {
    final items = _sortItems(widget.state.filteredItems);
    final bottomPadding = 88 + MediaQuery.viewPaddingOf(context).bottom;

    return Builder(
      builder: (ctx) => RefreshIndicator(
        onRefresh: () {
          widget.searchController.clear();
          return context.read<InventoryListCubit>().loadInventory();
        },
        child: CollapsingInnerScrollBody(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.horizontalMediumPadding.copyWith(
                  top: AppSpacing.verticalMedium,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextField(
                          controller: widget.searchController,
                          style: AppTextStyles.bodyLarge,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: 'بحث باسم الصنف أو رمز SKU...',
                            hintStyle: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.textTertiary,
                            ),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: widget.searchController.text.isNotEmpty
                                ? AppIconButton(
                                    icon: Icons.clear,
                                    variant: AppIconButtonVariant.text,
                                    onPressed: () {
                                      widget.searchController.clear();
                                      context
                                          .read<InventoryListCubit>()
                                          .setSearch('');
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppConstants.borderRadiusMedium,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.horizontalLarge,
                              vertical: 0,
                            ),
                          ),
                          onChanged: (v) {
                            context.read<InventoryListCubit>().setSearch(v);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.horizontalSmall),
                    SizedBox.square(
                      dimension: 42,
                      child: IconButton.outlined(
                        icon: Icon(
                          _filtersVisible
                              ? Icons.filter_alt_off_outlined
                              : Icons.filter_alt_outlined,
                        ),
                        tooltip: _filtersVisible
                            ? 'إخفاء الفلاتر'
                            : 'إظهار الفلاتر',
                        onPressed: () =>
                            setState(() => _filtersVisible = !_filtersVisible),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_filtersVisible)
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.horizontalMediumPadding.copyWith(
                    top: AppSpacing.verticalSmall,
                  ),
                  child: _InventoryManagementFilterCard(
                    state: widget.state,
                    viewMode: _viewMode,
                    onViewModeChanged: (mode) =>
                        setState(() => _viewMode = mode),
                    sortMode: _sortMode,
                    onSortModeChanged: (mode) {
                      setState(() => _sortMode = mode);
                      if (mode == _InventorySortMode.mostUsed) {
                        context.read<InventoryListCubit>().loadUsageCounts();
                      }
                    },
                    onCreate: widget.onCreate,
                    onBulkEdit: widget.onBulkEdit,
                    onImport: widget.onImport,
                    onBulkEditExcel: widget.onBulkEditExcel,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'لا توجد عناصر تطابق البحث',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              )
            else if (_viewMode == _InventoryViewMode.grid)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.horizontalMedium,
                  AppSpacing.verticalMedium,
                  AppSpacing.horizontalMedium,
                  bottomPadding,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 230,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _InventoryManagementGridCard(
                      item: items[i],
                      onTap: () => widget.onTap(items[i]),
                    ),
                    childCount: items.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => InventoryItemCard(
                      item: items[i],
                      onTap: () => widget.onTap(items[i]),
                    ),
                    childCount: items.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<InventoryItem> _sortItems(List<InventoryItem> items) {
    final sorted = List<InventoryItem>.from(items);
    sorted.sort((a, b) {
      final result = switch (_sortMode) {
        _InventorySortMode.name => a.itemName.compareTo(b.itemName),
        _InventorySortMode.mostUsed => (b.usageCount ?? 0).compareTo(a.usageCount ?? 0),
        _InventorySortMode.highestQuantity => b.quantity.compareTo(a.quantity),
        _InventorySortMode.lowStockFirst => _stockPriority(
          a,
        ).compareTo(_stockPriority(b)),
      };
      if (result != 0) return result;
      return a.itemName.compareTo(b.itemName);
    });
    return sorted;
  }

  int _stockPriority(InventoryItem item) {
    return switch (item.availabilityStatus) {
      AvailabilityStatus.outOfStock => 0,
      AvailabilityStatus.low => 1,
      AvailabilityStatus.available => 2,
    };
  }
}

class _InventoryManagementFilterCard extends StatelessWidget {
  final InventoryListLoaded state;
  final _InventoryViewMode viewMode;
  final ValueChanged<_InventoryViewMode> onViewModeChanged;
  final _InventorySortMode sortMode;
  final ValueChanged<_InventorySortMode> onSortModeChanged;
  final VoidCallback onCreate;
  final VoidCallback onBulkEdit;
  final VoidCallback onImport;
  final VoidCallback onBulkEditExcel;

  const _InventoryManagementFilterCard({
    required this.state,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.onCreate,
    required this.onBulkEdit,
    required this.onImport,
    required this.onBulkEditExcel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterSection(
              title: 'إدارة',
              icon: Icons.tune_outlined,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ManagementActionChip(
                    icon: Icons.add,
                    label: 'إضافة صنف',
                    onPressed: onCreate,
                  ),
                  _ManagementActionChip(
                    icon: Icons.edit_note_outlined,
                    label: 'تعديل الكميات',
                    onPressed: onBulkEdit,
                  ),
                  _ManagementActionChip(
                    icon: Icons.upload_file_outlined,
                    label: 'استيراد Excel',
                    onPressed: onImport,
                  ),
                  _ManagementActionChip(
                    icon: Icons.sync_alt_outlined,
                    label: 'تعديل Excel',
                    onPressed: onBulkEditExcel,
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.verticalMedium),
            _FilterSection(
              title: 'العرض',
              icon: Icons.view_module_outlined,
              child: SegmentedButton<_InventoryViewMode>(
                showSelectedIcon: false,
                segments: _InventoryViewMode.values
                    .map(
                      (mode) => ButtonSegment(
                        value: mode,
                        icon: Icon(mode.icon, size: 18),
                        label: Text(mode.label),
                      ),
                    )
                    .toList(),
                selected: {viewMode},
                onSelectionChanged: (selection) =>
                    onViewModeChanged(selection.first),
              ),
            ),
            SizedBox(height: AppSpacing.verticalMedium),
            _FilterSection(
              title: 'الترتيب',
              icon: Icons.sort,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _InventorySortMode.values
                    .map(
                      (mode) => ChoiceChip(
                        label: Text(mode.label),
                        selected: sortMode == mode,
                        onSelected: (_) => onSortModeChanged(mode),
                      ),
                    )
                    .toList(),
              ),
            ),
            SizedBox(height: AppSpacing.verticalMedium),
            _FilterSection(
              title: 'الحالة',
              icon: Icons.inventory_2_outlined,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _StatusFilterChip(
                    label: 'متوفر',
                    status: AvailabilityStatus.available,
                    color: SemanticColors.success,
                  ),
                  _StatusFilterChip(
                    label: 'منخفض',
                    status: AvailabilityStatus.low,
                    color: SemanticColors.warning,
                  ),
                  _StatusFilterChip(
                    label: 'نفد',
                    status: AvailabilityStatus.outOfStock,
                    color: SemanticColors.error,
                  ),
                ],
              ),
            ),
            if (state.availableCategories.isNotEmpty) ...[
              SizedBox(height: AppSpacing.verticalMedium),
              _FilterSection(
                title: 'الفئة',
                icon: Icons.category_outlined,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: state.availableCategories
                      .map(
                        (cat) => FilterChip(
                          label: Text(cat, style: AppTextStyles.bodyMedium),
                          selected: state.selectedCategory == cat,
                          onSelected: (on) => context
                              .read<InventoryListCubit>()
                              .setCategory(on ? cat : null),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final AvailabilityStatus status;
  final Color color;

  const _StatusFilterChip({
    required this.label,
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryListCubit>().state;
    final selected =
        state is InventoryListLoaded && state.statusFilter == status;
    return FilterChip(
      label: Text(label, style: AppTextStyles.bodyMedium),
      selected: selected,
      selectedColor: color.withAlpha(40),
      checkmarkColor: color,
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: selected ? color : null,
        fontWeight: selected ? FontWeight.bold : null,
      ),
      side: selected ? BorderSide(color: color) : null,
      onSelected: (on) => context.read<InventoryListCubit>().setStatusFilter(
        on ? status : null,
      ),
    );
  }
}

class _ManagementActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ManagementActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _FilterSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            SizedBox(width: AppSpacing.horizontalXSmall),
            Text(
              title,
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.verticalSmall),
        child,
      ],
    );
  }
}

class _InventoryManagementGridCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onTap;

  const _InventoryManagementGridCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockColor = switch (item.availabilityStatus) {
      AvailabilityStatus.available => SemanticColors.success,
      AvailabilityStatus.low => SemanticColors.warning,
      AvailabilityStatus.outOfStock => SemanticColors.error,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        child: Padding(
          padding: AppSpacing.allMedium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: stockColor, size: 24),
                  const Spacer(),
                  Text(
                    '${item.quantity}',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: stockColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.verticalSmall),
              Text(
                item.itemName,
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: AppSpacing.verticalXSmall),
              Text(
                item.unit,
                style: AppTextStyles.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: AppSpacing.verticalXSmall),
              Text(
                'الحد الأدنى: ${item.minQuantity}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              if (item.category != null || item.sku != null)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (item.category != null) _MiniTag(label: item.category!),
                    if (item.sku != null) _MiniTag(label: 'SKU: ${item.sku}'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;

  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
