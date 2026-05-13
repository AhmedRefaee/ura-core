import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_list_cubit.dart';
import 'widgets/inventory_item_card.dart';

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
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: BlocBuilder<InventoryListCubit, InventoryListState>(
        builder: (context, state) {
          if (state is InventoryListLoading || state is InventoryListInitial) {
            return const Center(child: AppLoadingIndicator());
          }
          if (state is InventoryListError) {
            return Center(
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
            );
          }
          if (state is InventoryListLoaded) {
            return _LoadedView(
              state: state,
              searchController: _searchController,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  final InventoryListLoaded state;
  final TextEditingController searchController;

  const _LoadedView({required this.state, required this.searchController});

  @override
  Widget build(BuildContext context) {
    final items = state.filteredItems;

    return Column(
      children: [
        Padding(
          padding: AppSpacing.horizontalMediumPadding.copyWith(top: AppSpacing.verticalMedium),
          child: TextField(
            controller: searchController,
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: 'بحث باسم الصنف أو رمز SKU...',
              hintStyle: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textTertiary,
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isNotEmpty
                  ? AppIconButton(
                      icon: Icons.clear,
                      variant: AppIconButtonVariant.text,
                      onPressed: () {
                        searchController.clear();
                        context.read<InventoryListCubit>().setSearch('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.horizontalLarge,
                vertical: 0,
              ),
            ),
            onChanged: (v) => context.read<InventoryListCubit>().setSearch(v),
          ),
        ),
        SizedBox(height: AppSpacing.verticalSmall),
        _FilterRow(state: state),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () {
              searchController.clear();
              return context.read<InventoryListCubit>().loadInventory();
            },
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد عناصر تطابق البحث',
                      style: AppTextStyles.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => InventoryItemCard(item: items[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  final InventoryListLoaded state;
  const _FilterRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: AppSpacing.horizontalMediumPadding,
      child: Row(
        children: [
          // Availability status filters
          _StatusFilterChip(
            label: 'متوفر',
            status: AvailabilityStatus.available,
            color: SemanticColors.success,
            selected: state.statusFilter == AvailabilityStatus.available,
          ),
          SizedBox(width: AppSpacing.horizontalXSmall),
          _StatusFilterChip(
            label: 'منخفض',
            status: AvailabilityStatus.low,
            color: SemanticColors.warning,
            selected: state.statusFilter == AvailabilityStatus.low,
          ),
          SizedBox(width: AppSpacing.horizontalXSmall),
          _StatusFilterChip(
            label: 'نفد',
            status: AvailabilityStatus.outOfStock,
            color: SemanticColors.error,
            selected: state.statusFilter == AvailabilityStatus.outOfStock,
          ),
          // Category filters
          if (state.availableCategories.isNotEmpty) ...[
            SizedBox(width: AppSpacing.horizontalMedium),
            const VerticalDivider(width: 1),
            SizedBox(width: AppSpacing.horizontalMedium),
            ...state.availableCategories.map((cat) => Padding(
                  padding: EdgeInsets.only(right: AppSpacing.horizontalXSmall),
                  child: FilterChip(
                    label: Text(cat, style: AppTextStyles.bodyMedium),
                    selected: state.selectedCategory == cat,
                    onSelected: (on) => context
                        .read<InventoryListCubit>()
                        .setCategory(on ? cat : null),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final AvailabilityStatus status;
  final Color color;
  final bool selected;

  const _StatusFilterChip({
    required this.label,
    required this.status,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
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
      onSelected: (on) => context
          .read<InventoryListCubit>()
          .setStatusFilter(on ? status : null),
    );
  }
}
