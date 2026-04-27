import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
            builder: (context, state) => IconButton(
              icon: const Icon(Icons.refresh),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Availability status filters
          _StatusFilterChip(
            label: 'متوفر',
            status: AvailabilityStatus.available,
            color: Colors.green,
            selected: state.statusFilter == AvailabilityStatus.available,
          ),
          const SizedBox(width: 6),
          _StatusFilterChip(
            label: 'منخفض',
            status: AvailabilityStatus.low,
            color: Colors.orange,
            selected: state.statusFilter == AvailabilityStatus.low,
          ),
          const SizedBox(width: 6),
          _StatusFilterChip(
            label: 'نفد',
            status: AvailabilityStatus.outOfStock,
            color: Colors.red,
            selected: state.statusFilter == AvailabilityStatus.outOfStock,
          ),
          // Category filters
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
