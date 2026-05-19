import 'package:flutter/material.dart';

import '../models/order.dart';

enum OrderSortMode {
  mostRecent,
  oldest,
  rep,
  entity,
  frequent,
}

enum OrderDirectionFilter {
  all,
  incoming,
  outgoing,
}

extension OrderSortModeLabel on OrderSortMode {
  String get label => switch (this) {
        OrderSortMode.mostRecent => 'الأحدث',
        OrderSortMode.oldest => 'الأقدم',
        OrderSortMode.rep => 'المندوب',
        OrderSortMode.entity => 'الجهة',
        OrderSortMode.frequent => 'الأكثر تكراراً',
      };
}

extension OrderDirectionFilterLabel on OrderDirectionFilter {
  String get label => switch (this) {
        OrderDirectionFilter.all => 'الكل',
        OrderDirectionFilter.incoming => 'وارد',
        OrderDirectionFilter.outgoing => 'صادر',
      };
}

DateTime _orderDate(Order order) {
  return order.deliveredAt ??
      order.moveStartedAt ??
      order.pickedUpAt ??
      order.assignedAt ??
      order.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

List<Order> sortOrders(List<Order> orders, OrderSortMode mode) {
  final sorted = List<Order>.from(orders);
  final entityCounts = <String, int>{};
  for (final order in sorted) {
    entityCounts[order.entityId] = (entityCounts[order.entityId] ?? 0) + 1;
  }

  sorted.sort((a, b) {
    final result = switch (mode) {
      OrderSortMode.mostRecent => _orderDate(b).compareTo(_orderDate(a)),
      OrderSortMode.oldest => _orderDate(a).compareTo(_orderDate(b)),
      OrderSortMode.rep => (a.rep?.fullName ?? '').compareTo(b.rep?.fullName ?? ''),
      OrderSortMode.entity => (a.entity?.name ?? '').compareTo(b.entity?.name ?? ''),
      OrderSortMode.frequent => (entityCounts[b.entityId] ?? 0).compareTo(entityCounts[a.entityId] ?? 0),
    };
    if (result != 0) return result;
    return _orderDate(b).compareTo(_orderDate(a));
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
        order.directionLabel.toLowerCase().contains(q);
  }).toList();
}

List<Order> filterOrdersByDirection(
  List<Order> orders,
  OrderDirectionFilter filter,
) {
  return switch (filter) {
    OrderDirectionFilter.all => orders,
    OrderDirectionFilter.incoming => orders
        .where((order) => order.direction != OrderDirection.outbound)
        .toList(),
    OrderDirectionFilter.outgoing => orders
        .where((order) => order.direction == OrderDirection.outbound)
        .toList(),
  };
}

class OrderSortFilterBar extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final OrderSortMode sortMode;
  final ValueChanged<OrderSortMode> onSortModeChanged;
  final OrderDirectionFilter directionFilter;
  final ValueChanged<OrderDirectionFilter> onDirectionFilterChanged;
  final bool? groupByEntity;
  final ValueChanged<bool>? onGroupByEntityChanged;
  final String searchHint;

  const OrderSortFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    this.groupByEntity,
    this.onGroupByEntityChanged,
    this.searchHint = 'بحث...',
  });

  @override
  State<OrderSortFilterBar> createState() => _OrderSortFilterBarState();
}

class _OrderSortFilterBarState extends State<OrderSortFilterBar> {
  late final TextEditingController _controller;

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
        ..selection = TextSelection.collapsed(offset: widget.searchQuery.length);
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onSearchChanged,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: Icon(Icons.sort, size: 18),
                ),
                ...OrderSortMode.values.map(
                  (mode) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(mode.label),
                      selected: widget.sortMode == mode,
                      onSelected: (_) => widget.onSortModeChanged(mode),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: Icon(Icons.swap_horiz, size: 18),
                ),
                ...OrderDirectionFilter.values.map(
                  (filter) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: widget.directionFilter == filter,
                      onSelected: (_) =>
                          widget.onDirectionFilterChanged(filter),
                    ),
                  ),
                ),
                if (widget.groupByEntity != null &&
                    widget.onGroupByEntityChanged != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: FilterChip(
                      avatar:
                          const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('تجميع حسب الجهة'),
                      selected: widget.groupByEntity!,
                      onSelected: widget.onGroupByEntityChanged,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
