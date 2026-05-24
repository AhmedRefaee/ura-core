import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order.dart';
import 'order_list_tile.dart';

enum OrderSortMode { mostRecent, oldest, frequent }

enum OrderDirectionFilter { all, inboundRep, inboundExternal, outbound }

enum OrderGroupMode { entity, rep }

enum OrderViewMode { list, grid }

extension OrderSortModeLabel on OrderSortMode {
  String get label => switch (this) {
    OrderSortMode.mostRecent => 'الأحدث',
    OrderSortMode.oldest => 'الأقدم',
    OrderSortMode.frequent => 'الأكثر تكراراً',
  };
}

extension OrderDirectionFilterLabel on OrderDirectionFilter {
  String get label => switch (this) {
    OrderDirectionFilter.all => 'الكل',
    OrderDirectionFilter.inboundRep => 'وارد عبر مندوب',
    OrderDirectionFilter.inboundExternal => 'وارد خارجي',
    OrderDirectionFilter.outbound => 'صادر عبر مندوب',
  };
}

extension OrderGroupModeLabel on OrderGroupMode {
  String get label => switch (this) {
    OrderGroupMode.entity => 'حسب الجهة',
    OrderGroupMode.rep => 'حسب المندوب',
  };
}

extension OrderViewModeLabel on OrderViewMode {
  String get label => switch (this) {
    OrderViewMode.list => 'قائمة',
    OrderViewMode.grid => 'شبكة',
  };

  IconData get icon => switch (this) {
    OrderViewMode.list => Icons.view_list_outlined,
    OrderViewMode.grid => Icons.grid_view_outlined,
  };
}

class OrderGroup {
  final String key;
  final String label;
  final List<Order> orders;
  final List<OrderGroup> children;

  const OrderGroup({
    required this.key,
    required this.label,
    required this.orders,
    this.children = const [],
  });

  int get count => orders.length;
}

typedef OrderItemBuilder = Widget Function(BuildContext context, Order order);

class GroupedOrdersSliver extends StatelessWidget {
  final List<OrderGroup> groups;
  final OrderItemBuilder orderBuilder;
  final OrderViewMode viewMode;
  final bool initiallyExpandSingleGroup;

  const GroupedOrdersSliver({
    super.key,
    required this.groups,
    required this.orderBuilder,
    this.viewMode = OrderViewMode.list,
    this.initiallyExpandSingleGroup = true,
  });

  @override
  Widget build(BuildContext context) {
    final autoExpand = initiallyExpandSingleGroup && groups.length == 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _GroupTile(
          group: groups[index],
          depth: 0,
          initiallyExpanded: autoExpand,
          orderBuilder: orderBuilder,
          viewMode: viewMode,
        ),
        childCount: groups.length,
      ),
    );
  }
}

class OrdersGridSliver extends StatelessWidget {
  final List<Order> orders;
  final OrderItemBuilder orderBuilder;

  const OrdersGridSliver({
    super.key,
    required this.orders,
    required this.orderBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final count = width >= 900
              ? 4
              : width >= 640
              ? 3
              : 2;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: _orderGridTileExtent(width, count),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => orderBuilder(context, orders[index]),
              childCount: orders.length,
            ),
          );
        },
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final OrderGroup group;
  final int depth;
  final bool initiallyExpanded;
  final OrderItemBuilder orderBuilder;
  final OrderViewMode viewMode;

  const _GroupTile({
    required this.group,
    required this.depth,
    required this.initiallyExpanded,
    required this.orderBuilder,
    required this.viewMode,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tile = ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      title: Text(
        group.label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.primary.withAlpha(20),
          border: Border.all(color: colorScheme.primary),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${group.count} ${group.count == 1 ? 'طلب' : 'طلبات'}',
          style: TextStyle(
            color: colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      children: group.children.isNotEmpty
          ? group.children
                .map(
                  (child) => _GroupTile(
                    group: child,
                    depth: depth + 1,
                    initiallyExpanded: initiallyExpanded,
                    orderBuilder: orderBuilder,
                    viewMode: viewMode,
                  ),
                )
                .toList()
          : _buildOrderChildren(context),
    );

    if (depth == 0) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxIndent = constraints.maxWidth * 0.04;
        final indent = math.min(12.0 * depth, maxIndent);
        return Padding(
          padding: EdgeInsetsDirectional.only(start: indent),
          child: tile,
        );
      },
    );
  }

  List<Widget> _buildOrderChildren(BuildContext context) {
    if (viewMode == OrderViewMode.list) {
      return group.orders
          .map(
            (order) => GroupedOrderScope(
              insetCard: true,
              child: orderBuilder(context, order),
            ),
          )
          .toList();
    }

    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 380;
          final hPad = narrow ? 6.0 : 12.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 12),
            child: LayoutBuilder(
              builder: (context, innerConstraints) {
                final count = innerConstraints.maxWidth >= 560 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: _orderGridTileExtent(
                      innerConstraints.maxWidth,
                      count,
                    ),
                  ),
                  itemBuilder: (context, index) =>
                      orderBuilder(context, group.orders[index]),
                  itemCount: group.orders.length,
                );
              },
            ),
          );
        },
      ),
    ];
  }
}

double _orderGridTileExtent(double availableWidth, int columnCount) {
  const spacing = 10.0;
  final tileWidth =
      (availableWidth - (spacing * (columnCount - 1))) / columnCount;

  if (tileWidth < 180) return 268;
  if (tileWidth < 240) return 252;
  return 236;
}

DateTime orderSortDate(Order order) {
  return order.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

List<Order> sortOrders(List<Order> orders, OrderSortMode mode) {
  final sorted = List<Order>.from(orders);
  final entityCounts = <String, int>{};
  for (final order in sorted) {
    entityCounts[order.entityId] = (entityCounts[order.entityId] ?? 0) + 1;
  }

  sorted.sort((a, b) {
    final result = switch (mode) {
      OrderSortMode.mostRecent => orderSortDate(b).compareTo(orderSortDate(a)),
      OrderSortMode.oldest => orderSortDate(a).compareTo(orderSortDate(b)),
      OrderSortMode.frequent => (entityCounts[b.entityId] ?? 0).compareTo(
        entityCounts[a.entityId] ?? 0,
      ),
    };
    if (result != 0) return result;
    return orderSortDate(b).compareTo(orderSortDate(a));
  });
  return sorted;
}

List<Order> filterOrdersByQuery(List<Order> orders, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return orders;
  return orders.where((order) {
    return (order.entity?.name ?? '').toLowerCase().contains(q) ||
        (order.rep?.fullName ?? '').toLowerCase().contains(q) ||
        order.statusLabel.toLowerCase().contains(q) ||
        order.directionLabel.toLowerCase().contains(q) ||
        (order.referenceCode ?? '').toLowerCase().contains(q);
  }).toList();
}

List<Order> filterOrdersByDirection(
  List<Order> orders,
  OrderDirectionFilter filter,
) {
  return switch (filter) {
    OrderDirectionFilter.all => orders,
    OrderDirectionFilter.inboundRep =>
      orders
          .where((order) => order.direction == OrderDirection.inboundRep)
          .toList(),
    OrderDirectionFilter.inboundExternal =>
      orders
          .where((order) => order.direction == OrderDirection.inboundExternal)
          .toList(),
    OrderDirectionFilter.outbound =>
      orders
          .where((order) => order.direction == OrderDirection.outbound)
          .toList(),
  };
}

List<Order> prepareOrders(
  List<Order> orders, {
  required String searchQuery,
  required OrderDirectionFilter directionFilter,
}) {
  return filterOrdersByDirection(
    filterOrdersByQuery(orders, searchQuery),
    directionFilter,
  );
}

List<OrderGroup> groupOrders(
  List<Order> orders, {
  required List<OrderGroupMode> groupModes,
  required OrderSortMode sortMode,
}) {
  if (groupModes.isEmpty) return const [];
  return _buildGroups(orders, groupModes, 0, sortMode);
}

List<OrderGroup> _buildGroups(
  List<Order> orders,
  List<OrderGroupMode> modes,
  int depth,
  OrderSortMode sortMode,
) {
  final mode = modes[depth];
  final grouped = <String, List<Order>>{};
  final labels = <String, String>{};

  for (final order in orders) {
    final key = _groupKey(order, mode);
    grouped.putIfAbsent(key, () => []).add(order);
    labels[key] = _groupLabel(order, mode);
  }

  final groups = grouped.entries.map((entry) {
    final groupOrders = entry.value;
    final isLeaf = depth == modes.length - 1;
    return OrderGroup(
      key: '${mode.name}:${entry.key}',
      label: labels[entry.key] ?? '—',
      orders: isLeaf ? sortOrders(groupOrders, sortMode) : groupOrders,
      children: isLeaf
          ? const []
          : _buildGroups(groupOrders, modes, depth + 1, sortMode),
    );
  }).toList();

  groups.sort((a, b) => _compareGroups(a, b, sortMode));
  return groups;
}

String _groupKey(Order order, OrderGroupMode mode) {
  return switch (mode) {
    OrderGroupMode.entity => order.entityId,
    OrderGroupMode.rep => order.repId ?? 'unassigned',
  };
}

String _groupLabel(Order order, OrderGroupMode mode) {
  return switch (mode) {
    OrderGroupMode.entity => order.entity?.name ?? 'بدون جهة',
    OrderGroupMode.rep => order.rep?.fullName ?? 'بدون مندوب',
  };
}

int _compareGroups(OrderGroup a, OrderGroup b, OrderSortMode mode) {
  final result = switch (mode) {
    OrderSortMode.mostRecent => _latestDate(
      b.orders,
    ).compareTo(_latestDate(a.orders)),
    OrderSortMode.oldest => _earliestDate(
      a.orders,
    ).compareTo(_earliestDate(b.orders)),
    OrderSortMode.frequent => b.count.compareTo(a.count),
  };
  if (result != 0) return result;
  return a.label.compareTo(b.label);
}

DateTime _latestDate(List<Order> orders) {
  return orders.map(orderSortDate).reduce((a, b) => a.isAfter(b) ? a : b);
}

DateTime _earliestDate(List<Order> orders) {
  return orders.map(orderSortDate).reduce((a, b) => a.isBefore(b) ? a : b);
}

class OrderSortFilterBar extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final OrderSortMode sortMode;
  final ValueChanged<OrderSortMode> onSortModeChanged;
  final OrderDirectionFilter directionFilter;
  final ValueChanged<OrderDirectionFilter> onDirectionFilterChanged;
  final OrderViewMode viewMode;
  final ValueChanged<OrderViewMode> onViewModeChanged;
  final bool? groupByEntity;
  final ValueChanged<bool>? onGroupByEntityChanged;
  final bool? groupByRep;
  final ValueChanged<bool>? onGroupByRepChanged;
  final String searchHint;

  const OrderSortFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    this.groupByEntity,
    this.onGroupByEntityChanged,
    this.groupByRep,
    this.onGroupByRepChanged,
    this.searchHint = 'بحث...',
  });

  @override
  State<OrderSortFilterBar> createState() => _OrderSortFilterBarState();
}

class _OrderSortFilterBarState extends State<OrderSortFilterBar> {
  late final TextEditingController _controller;
  bool _filtersVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant OrderSortFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _controller.text) {
      _controller
        ..text = widget.searchQuery
        ..selection = TextSelection.collapsed(
          offset: widget.searchQuery.length,
        );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _controller,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _controller.clear();
                                widget.onSearchChanged('');
                                setState(() {});
                              },
                            ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      widget.onSearchChanged(value);
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 42,
                child: IconButton.outlined(
                  icon: Icon(
                    _filtersVisible
                        ? Icons.filter_alt_off_outlined
                        : Icons.filter_alt_outlined,
                  ),
                  tooltip: _filtersVisible ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
                  onPressed: () =>
                      setState(() => _filtersVisible = !_filtersVisible),
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _filtersVisible
                ? Padding(
                    key: const ValueKey('filters'),
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildFilterCard(),
                  )
                : const SizedBox.shrink(key: ValueKey('filters-hidden')),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterSection(
              title: 'العرض',
              icon: Icons.view_module_outlined,
              child: SegmentedButton<OrderViewMode>(
                showSelectedIcon: false,
                segments: OrderViewMode.values
                    .map(
                      (mode) => ButtonSegment(
                        value: mode,
                        icon: Icon(mode.icon, size: 18),
                        label: Text(mode.label),
                      ),
                    )
                    .toList(),
                selected: {widget.viewMode},
                onSelectionChanged: (selection) =>
                    widget.onViewModeChanged(selection.first),
              ),
            ),
            const SizedBox(height: 12),
            _FilterSection(
              title: 'الترتيب',
              icon: Icons.sort,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OrderSortMode.values
                    .map(
                      (mode) => ChoiceChip(
                        label: Text(mode.label),
                        selected: widget.sortMode == mode,
                        onSelected: (_) => widget.onSortModeChanged(mode),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_hasGroupingControls) ...[
              const SizedBox(height: 12),
              _FilterSection(
                title: 'التجميع',
                icon: Icons.account_tree_outlined,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.groupByEntity != null &&
                        widget.onGroupByEntityChanged != null)
                      FilterChip(
                        label: Text(OrderGroupMode.entity.label),
                        selected: widget.groupByEntity!,
                        onSelected: widget.onGroupByEntityChanged,
                      ),
                    if (widget.groupByRep != null &&
                        widget.onGroupByRepChanged != null)
                      FilterChip(
                        label: Text(OrderGroupMode.rep.label),
                        selected: widget.groupByRep!,
                        onSelected: widget.onGroupByRepChanged,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _FilterSection(
              title: 'الاتجاه',
              icon: Icons.swap_horiz,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OrderDirectionFilter.values
                    .map(
                      (filter) => ChoiceChip(
                        label: Text(filter.label),
                        selected: widget.directionFilter == filter,
                        onSelected: (_) =>
                            widget.onDirectionFilterChanged(filter),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasGroupingControls {
    return (widget.groupByEntity != null &&
            widget.onGroupByEntityChanged != null) ||
        (widget.groupByRep != null && widget.onGroupByRepChanged != null);
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
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
