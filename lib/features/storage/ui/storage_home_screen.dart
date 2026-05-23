import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../../shared/widgets/order_sort_filter_bar.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../chat/logic/chat_threads_cubit.dart';
import '../../chat/ui/chat_hub_screen.dart';
import '../../notifications/logic/chat_badge_cubit.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../../inventory/ui/inventory_management_screen.dart';
import '../../profile/ui/profile_screen.dart';
import '../logic/storage_order_detail_cubit.dart';
import '../logic/storage_orders_cubit.dart';
import 'storage_order_detail_screen.dart';

class StorageHomeScreen extends StatelessWidget {
  const StorageHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<StorageOrdersCubit>()..loadOrders()),
        BlocProvider.value(value: sl<NotificationsBadgeCubit>()),
        BlocProvider.value(value: sl<ChatBadgeCubit>()),
        BlocProvider(create: (_) => sl<ChatThreadsCubit>()..loadThreads()),
      ],
      child: const _StorageHomeView(),
    );
  }
}

class _StorageHomeView extends StatefulWidget {
  const _StorageHomeView();

  @override
  State<_StorageHomeView> createState() => _StorageHomeViewState();
}

class _StorageHomeViewState extends State<_StorageHomeView> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_navIndex) {
        0 => const _OrdersTab(),
        1 => const InventoryManagementScreen(),
        2 => const ChatHubSection(),
        3 => _SettingsTab(onLogout: () => context.read<AuthCubit>().signOut()),
        _ => const SizedBox.shrink(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'الطلبات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'المخزون',
          ),
          NavigationDestination(
            icon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => NotificationDot(
                isVisible: count > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            selectedIcon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => NotificationDot(
                isVisible: count > 0,
                child: const Icon(Icons.chat_bubble),
              ),
            ),
            label: 'المحادثات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

// ── Orders Tab ────────────────────────────────────────────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab>
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
      title: const Text('بوابة المخزن'),
      actions: [
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.push('/notifications'),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<StorageOrdersCubit>().loadOrders(),
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
      body: BlocBuilder<StorageOrdersCubit, StorageOrdersState>(
        builder: (context, state) {
          if (state is StorageOrdersLoading || state is StorageOrdersInitial) {
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
          if (state is StorageOrdersError) {
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
                                context.read<StorageOrdersCubit>().loadOrders(),
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
          if (state is StorageOrdersLoaded) {
            return TabBarView(
              controller: _tabController,
              children: [
                _OrderList(
                  orders: state.activeOrders,
                  emptyMessage: 'لا توجد طلبات تحتاج إجراء',
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
                  onRefresh: () =>
                      context.read<StorageOrdersCubit>().loadOrders(),
                  onTap: (id) => _openDetail(context, id),
                ),
                _OrderList(
                  orders: state.doneOrders,
                  emptyMessage: 'لا توجد طلبات مكتملة',
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
                  onRefresh: () =>
                      context.read<StorageOrdersCubit>().loadOrders(),
                  onTap: (id) => _openDetail(context, id),
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

  void _openDetail(BuildContext context, String orderId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) =>
              sl.get<StorageOrderDetailCubit>(param1: orderId)..load(),
          child: const StorageOrderDetailScreen(),
        ),
      ),
    );
    if (context.mounted) {
      context.read<StorageOrdersCubit>().loadOrders();
    }
  }
}

// ── Order list ────────────────────────────────────────────────────────────────

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
  final Future<void> Function() onRefresh;
  final void Function(String orderId) onTap;

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
    required this.onRefresh,
    required this.onTap,
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
        onRefresh: onRefresh,
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
                orderBuilder: (_, order) => viewMode == OrderViewMode.grid
                    ? OrderGridCard(order: order, onTap: () => onTap(order.id))
                    : OrderListTile(order: order, onTap: () => onTap(order.id)),
              )
            else if (viewMode == OrderViewMode.grid)
              OrdersGridSliver(
                orders: visible,
                orderBuilder: (_, order) =>
                    OrderGridCard(order: order, onTap: () => onTap(order.id)),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => OrderListTile(
                    order: visible[i],
                    onTap: () => onTap(visible[i].id),
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

// ── Settings tab ──────────────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final VoidCallback onLogout;

  const _SettingsTab({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('الإعدادات'),
      actions: [
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.push('/notifications'),
            ),
          ),
        ),
      ],
      body: Builder(
        builder: (ctx) => CollapsingInnerScrollBody(
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('ملفي الشخصي'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final state = context.read<AuthCubit>().state;
                    if (state is AuthAuthenticated) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(profile: state.profile),
                        ),
                      );
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('الإعدادات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('تسجيل الخروج'),
                  onTap: onLogout,
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
