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
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المخزون'),
        actions: [
          PopupMenuButton<_ExcelAction>(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'خيارات Excel',
            onSelected: (action) {
              if (action == _ExcelAction.importNew) _openImport(context);
              if (action == _ExcelAction.bulkEdit) _openBulkEditExcel(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ExcelAction.importNew,
                child: ListTile(
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('استيراد عناصر جديدة'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _ExcelAction.bulkEdit,
                child: ListTile(
                  leading: Icon(Icons.sync_alt_outlined),
                  title: Text('تعديل جماعي عبر Excel'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          AppIconButton(
            icon: Icons.edit_note_outlined,
            tooltip: 'تعديل الكميات',
            variant: AppIconButtonVariant.text,
            onPressed: () => _openBulkEdit(context),
          ),
          BlocBuilder<InventoryListCubit, InventoryListState>(
            builder: (context, state) => AppIconButton(
              icon: Icons.refresh,
              tooltip: 'تحديث',
              variant: AppIconButtonVariant.text,
              onPressed: () {
                _searchController.clear();
                context.read<InventoryListCubit>().loadInventory();
              },
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
              onTap: (item) => _openDetail(context, item),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: AppFloatingActionButton(
        onPressed: () => _openCreate(context),
        icon: Icons.add,
        label: 'إضافة صنف',
        isExtended: true,
      ),
    );
  }

  void _openDetail(BuildContext context, InventoryItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryItemDetailScreen(item: item),
      ),
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

class _LoadedView extends StatelessWidget {
  final InventoryListLoaded state;
  final TextEditingController searchController;
  final void Function(InventoryItem) onTap;

  const _LoadedView({
    required this.state,
    required this.searchController,
    required this.onTap,
  });

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
        SizedBox(height: AppSpacing.verticalXSmall),
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
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: items.length,
                    itemBuilder: (_, i) => InventoryItemCard(
                      item: items[i],
                      onTap: () => onTap(items[i]),
                    ),
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
          _statusChip(context, 'متوفر', AvailabilityStatus.available,
              SemanticColors.success),
          SizedBox(width: AppSpacing.horizontalXSmall),
          _statusChip(
              context, 'منخفض', AvailabilityStatus.low, SemanticColors.warning),
          SizedBox(width: AppSpacing.horizontalXSmall),
          _statusChip(
              context, 'نفد', AvailabilityStatus.outOfStock, SemanticColors.error),
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

  Widget _statusChip(BuildContext context, String label,
      AvailabilityStatus status, Color color) {
    final selected = state.statusFilter == status;
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
