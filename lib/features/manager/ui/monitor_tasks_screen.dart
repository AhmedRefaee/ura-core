import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../../shared/widgets/order_sort_filter_bar.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../logic/monitor_orders_cubit.dart';
import 'task_detail_screen.dart';

class MonitorTasksScreen extends StatefulWidget {
  const MonitorTasksScreen({super.key});

  @override
  State<MonitorTasksScreen> createState() => _MonitorTasksScreenState();
}

class _MonitorTasksScreenState extends State<MonitorTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  OrderSortMode _sortMode = OrderSortMode.mostRecent;
  OrderDirectionFilter _directionFilter = OrderDirectionFilter.all;
  OrderViewMode _viewMode = OrderViewMode.list;
  bool _groupByEntity = false;
  bool _groupByRep = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('لوحة المدير'),
      actions: [
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.go('/notifications'),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<MonitorOrdersCubit>().load(),
          tooltip: 'تحديث',
        ),
      ],
      sliverBottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'نشطة'),
          Tab(text: 'مكتملة'),
        ],
      ),
      body: BlocBuilder<MonitorOrdersCubit, MonitorOrdersState>(
        builder: (context, state) {
          if (state is MonitorOrdersLoading || state is MonitorOrdersInitial) {
            return Builder(
              builder: (ctx) => const CollapsingInnerScrollBody(
                slivers: [
                  SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            );
          }
          if (state is MonitorOrdersError) {
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
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () =>
                                context.read<MonitorOrdersCubit>().load(),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          if (state is MonitorOrdersLoaded) {
            return TabBarView(
              controller: _tabController,
              children: [
                _OrderList(
                  orders: state.activeOrders,
                  emptyMessage: 'لا توجد مهام نشطة',
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  onSortModeChanged: (mode) => setState(() => _sortMode = mode),
                  directionFilter: _directionFilter,
                  onDirectionFilterChanged: (filter) =>
                      setState(() => _directionFilter = filter),
                  viewMode: _viewMode,
                  onViewModeChanged: (mode) => setState(() => _viewMode = mode),
                  groupByEntity: _groupByEntity,
                  onGroupByEntityChanged: (value) =>
                      setState(() => _groupByEntity = value),
                  groupByRep: _groupByRep,
                  onGroupByRepChanged: (value) =>
                      setState(() => _groupByRep = value),
                ),
                _FinishedOrderList(
                  orders: state.finishedOrders,
                  hasMore: state.hasMoreFinished,
                  isLoadingMore: state.isLoadingMoreFinished,
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  onSortModeChanged: (mode) => setState(() => _sortMode = mode),
                  directionFilter: _directionFilter,
                  onDirectionFilterChanged: (filter) =>
                      setState(() => _directionFilter = filter),
                  viewMode: _viewMode,
                  onViewModeChanged: (mode) => setState(() => _viewMode = mode),
                  groupByEntity: _groupByEntity,
                  onGroupByEntityChanged: (value) =>
                      setState(() => _groupByEntity = value),
                  groupByRep: _groupByRep,
                  onGroupByRepChanged: (value) =>
                      setState(() => _groupByRep = value),
                ),
              ],
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

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  final String searchQuery;
  final OrderSortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<OrderSortMode> onSortModeChanged;
  final OrderDirectionFilter directionFilter;
  final ValueChanged<OrderDirectionFilter> onDirectionFilterChanged;
  final OrderViewMode viewMode;
  final ValueChanged<OrderViewMode> onViewModeChanged;
  final bool groupByEntity;
  final ValueChanged<bool> onGroupByEntityChanged;
  final bool groupByRep;
  final ValueChanged<bool> onGroupByRepChanged;
  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    required this.searchQuery,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.groupByEntity,
    required this.onGroupByEntityChanged,
    required this.groupByRep,
    required this.onGroupByRepChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = prepareOrders(
      orders,
      searchQuery: searchQuery,
      directionFilter: directionFilter,
    );
    final groupModes = [
      if (groupByEntity) OrderGroupMode.entity,
      if (groupByRep) OrderGroupMode.rep,
    ];
    final visible = groupModes.isEmpty
        ? sortOrders(filtered, sortMode)
        : <Order>[];
    final groups = groupModes.isEmpty
        ? const <OrderGroup>[]
        : groupOrders(filtered, groupModes: groupModes, sortMode: sortMode);

    return Builder(
      builder: (ctx) => RefreshIndicator(
        onRefresh: () => context.read<MonitorOrdersCubit>().load(),
        child: CollapsingInnerScrollBody(
          slivers: [
            SliverToBoxAdapter(
              child: OrderSortFilterBar(
                searchQuery: searchQuery,
                onSearchChanged: onSearchChanged,
                sortMode: sortMode,
                onSortModeChanged: onSortModeChanged,
                directionFilter: directionFilter,
                onDirectionFilterChanged: onDirectionFilterChanged,
                viewMode: viewMode,
                onViewModeChanged: onViewModeChanged,
                groupByEntity: groupByEntity,
                onGroupByEntityChanged: onGroupByEntityChanged,
                groupByRep: groupByRep,
                onGroupByRepChanged: onGroupByRepChanged,
                searchHint: 'بحث بالجهة أو المندوب...',
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(emptyMessage)),
              )
            else if (groupModes.isNotEmpty)
              GroupedOrdersSliver(
                groups: groups,
                viewMode: viewMode,
                orderBuilder: (context, order) => viewMode == OrderViewMode.grid
                    ? OrderGridCard(
                        order: order,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailScreen(orderId: order.id),
                          ),
                        ),
                      )
                    : OrderListTile(
                        order: order,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailScreen(orderId: order.id),
                          ),
                        ),
                      ),
              )
            else if (viewMode == OrderViewMode.grid)
              OrdersGridSliver(
                orders: visible,
                orderBuilder: (context, order) => OrderGridCard(
                  order: order,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskDetailScreen(orderId: order.id),
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => OrderListTile(
                    order: visible[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TaskDetailScreen(orderId: visible[i].id),
                      ),
                    ),
                  ),
                  childCount: visible.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FinishedOrderList extends StatefulWidget {
  final List<Order> orders;
  final bool hasMore;
  final bool isLoadingMore;
  final String searchQuery;
  final OrderSortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<OrderSortMode> onSortModeChanged;
  final OrderDirectionFilter directionFilter;
  final ValueChanged<OrderDirectionFilter> onDirectionFilterChanged;
  final OrderViewMode viewMode;
  final ValueChanged<OrderViewMode> onViewModeChanged;
  final bool groupByEntity;
  final ValueChanged<bool> onGroupByEntityChanged;
  final bool groupByRep;
  final ValueChanged<bool> onGroupByRepChanged;

  const _FinishedOrderList({
    required this.orders,
    required this.hasMore,
    required this.isLoadingMore,
    required this.searchQuery,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.groupByEntity,
    required this.onGroupByEntityChanged,
    required this.groupByRep,
    required this.onGroupByRepChanged,
  });

  @override
  State<_FinishedOrderList> createState() => _FinishedOrderListState();
}

class _FinishedOrderListState extends State<_FinishedOrderList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<MonitorOrdersCubit>().loadMoreFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = prepareOrders(
      widget.orders,
      searchQuery: widget.searchQuery,
      directionFilter: widget.directionFilter,
    );
    final groupModes = [
      if (widget.groupByEntity) OrderGroupMode.entity,
      if (widget.groupByRep) OrderGroupMode.rep,
    ];
    final orders = groupModes.isEmpty
        ? sortOrders(filtered, widget.sortMode)
        : <Order>[];
    final groups = groupModes.isEmpty
        ? const <OrderGroup>[]
        : groupOrders(
            filtered,
            groupModes: groupModes,
            sortMode: widget.sortMode,
          );
    final itemCount = orders.isEmpty
        ? 1
        : orders.length + (widget.hasMore ? 1 : 0);

    return Builder(
      builder: (ctx) => RefreshIndicator(
        onRefresh: () => context.read<MonitorOrdersCubit>().load(),
        child: CollapsingInnerScrollBody(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: OrderSortFilterBar(
                searchQuery: widget.searchQuery,
                onSearchChanged: widget.onSearchChanged,
                sortMode: widget.sortMode,
                onSortModeChanged: widget.onSortModeChanged,
                directionFilter: widget.directionFilter,
                onDirectionFilterChanged: widget.onDirectionFilterChanged,
                viewMode: widget.viewMode,
                onViewModeChanged: widget.onViewModeChanged,
                groupByEntity: widget.groupByEntity,
                onGroupByEntityChanged: widget.onGroupByEntityChanged,
                groupByRep: widget.groupByRep,
                onGroupByRepChanged: widget.onGroupByRepChanged,
                searchHint: 'بحث بالجهة أو المندوب...',
              ),
            ),
            if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('لا توجد مهام مكتملة')),
              )
            else if (groupModes.isNotEmpty)
              GroupedOrdersSliver(
                groups: groups,
                viewMode: widget.viewMode,
                orderBuilder: (context, order) =>
                    widget.viewMode == OrderViewMode.grid
                    ? OrderGridCard(
                        order: order,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailScreen(orderId: order.id),
                          ),
                        ),
                      )
                    : OrderListTile(
                        order: order,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailScreen(orderId: order.id),
                          ),
                        ),
                      ),
              )
            else if (widget.viewMode == OrderViewMode.grid)
              OrdersGridSliver(
                orders: orders,
                orderBuilder: (context, order) => OrderGridCard(
                  order: order,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskDetailScreen(orderId: order.id),
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  if (i == orders.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: widget.isLoadingMore
                          ? const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const SizedBox.shrink(),
                    );
                  }
                  return OrderListTile(
                    order: orders[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskDetailScreen(orderId: orders[i].id),
                      ),
                    ),
                  );
                }, childCount: itemCount),
              ),
          ],
        ),
      ),
    );
  }
}
