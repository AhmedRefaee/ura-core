import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_list_cubit.dart';
import 'inventory_bulk_edit_screen.dart';
import 'inventory_form_screen.dart';
import 'inventory_item_detail_screen.dart';
import 'widgets/inventory_item_card.dart';

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
          IconButton(
            icon: const Icon(Icons.edit_note_outlined),
            tooltip: 'تعديل الكميات',
            onPressed: () => _openBulkEdit(context),
          ),
          BlocBuilder<InventoryListCubit, InventoryListState>(
            builder: (context, state) => IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
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
            return const Center(child: CircularProgressIndicator());
          }
          if (state is InventoryListError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message,
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () =>
                        context.read<InventoryListCubit>().loadInventory(),
                    child: const Text('إعادة المحاولة'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة صنف'),
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'بحث باسم الصنف أو رمز SKU...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        context.read<InventoryListCubit>().setSearch('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
            onChanged: (v) => context.read<InventoryListCubit>().setSearch(v),
          ),
        ),
        const SizedBox(height: 8),
        _FilterRow(state: state),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () {
              searchController.clear();
              return context.read<InventoryListCubit>().loadInventory();
            },
            child: items.isEmpty
                ? const Center(child: Text('لا توجد عناصر تطابق البحث'))
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _statusChip(context, 'متوفر', AvailabilityStatus.available,
              Colors.green),
          const SizedBox(width: 6),
          _statusChip(
              context, 'منخفض', AvailabilityStatus.low, Colors.orange),
          const SizedBox(width: 6),
          _statusChip(
              context, 'نفد', AvailabilityStatus.outOfStock, Colors.red),
          if (state.availableCategories.isNotEmpty) ...[
            const SizedBox(width: 12),
            const VerticalDivider(width: 1),
            const SizedBox(width: 12),
            ...state.availableCategories.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat),
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
      label: Text(label),
      selected: selected,
      selectedColor: color.withAlpha(40),
      checkmarkColor: color,
      labelStyle: TextStyle(
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
