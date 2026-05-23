import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_list_cubit.dart';
import 'widgets/inventory_item_card.dart';

enum _InventoryViewMode { list, grid }

enum _InventorySortMode { name, mostUsed }

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
  };
}

class InventoryAvailabilityScreen extends StatelessWidget {
  const InventoryAvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<InventoryListCubit>()..loadInventory(),
      child: const _InventoryAvailabilityView(),
    );
  }
}

class _InventoryAvailabilityView extends StatefulWidget {
  const _InventoryAvailabilityView();

  @override
  State<_InventoryAvailabilityView> createState() =>
      _InventoryAvailabilityViewState();
}

class _InventoryAvailabilityViewState
    extends State<_InventoryAvailabilityView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('توافر المخزون'),
      actions: [
        BlocBuilder<InventoryListCubit, InventoryListState>(
          builder: (context, state) => AppIconButton(
            icon: Icons.refresh,
            variant: AppIconButtonVariant.text,
            onPressed: () {
              _searchController.clear();
              context.read<InventoryListCubit>().loadInventory();
            },
            tooltip: 'تحديث',
          ),
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
                            onPressed: () =>
                                context.read<InventoryListCubit>().loadInventory(),
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
}

class _LoadedView extends StatefulWidget {
  final InventoryListLoaded state;
  final TextEditingController searchController;

  const _LoadedView({required this.state, required this.searchController});

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
                        tooltip:
                            _filtersVisible ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
                        onPressed: () =>
                            setState(() => _filtersVisible = !_filtersVisible),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _filtersVisible
                    ? Padding(
                        key: const ValueKey('inventory-filters'),
                        padding: AppSpacing.horizontalMediumPadding.copyWith(
                          top: AppSpacing.verticalSmall,
                        ),
                        child: _InventoryFilterCard(
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
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('inventory-filters-hidden'),
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
                padding: AppSpacing.allMedium,
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _InventoryGridCard(item: items[i]),
                    childCount: items.length,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => InventoryItemCard(item: items[i]),
                  childCount: items.length,
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
      };
      if (result != 0) return result;
      return a.itemName.compareTo(b.itemName);
    });
    return sorted;
  }
}

class _InventoryFilterCard extends StatelessWidget {
  final InventoryListLoaded state;
  final _InventoryViewMode viewMode;
  final ValueChanged<_InventoryViewMode> onViewModeChanged;
  final _InventorySortMode sortMode;
  final ValueChanged<_InventorySortMode> onSortModeChanged;

  const _InventoryFilterCard({
    required this.state,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.sortMode,
    required this.onSortModeChanged,
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
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

class _InventoryGridCard extends StatelessWidget {
  final InventoryItem item;

  const _InventoryGridCard({required this.item});

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
            SizedBox(height: AppSpacing.verticalMedium),
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
