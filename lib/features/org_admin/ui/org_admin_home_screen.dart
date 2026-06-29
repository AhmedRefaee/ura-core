import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../chat/logic/chat_threads_cubit.dart';
import '../../chat/ui/chat_hub_screen.dart';
import '../../notifications/logic/chat_badge_cubit.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../../inventory/ui/inventory_management_screen.dart';
import '../../manager/logic/manager_pending_users_cubit.dart';
import '../../manager/logic/stats_cubit.dart';
import '../../manager/logic/user_type_cubit.dart';
import '../../manager/ui/manager_pending_users_screen.dart';
import '../../manager/ui/stats_screen.dart';
import '../../manager/ui/task_detail_screen.dart';
import '../../profile/ui/profile_screen.dart';
import '../../storage/logic/storage_order_detail_cubit.dart';
import '../../storage/logic/storage_orders_cubit.dart';
import '../../storage/ui/storage_order_detail_screen.dart';
import '../../verifier/logic/create_order_cubit.dart';
import '../../verifier/logic/orders_cubit.dart';
import '../../verifier/logic/orders_state.dart';
import '../../verifier/ui/create_order_screen.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../../shared/widgets/order_sort_filter_bar.dart';

/// Org-level admin shell: the union of manager + verifier + rep +
/// storage_actor capabilities within one organization, with a normal
/// bottom-nav shell like the other roles (unlike the standalone, cross-org
/// platform admin console).
class OrgAdminHomeScreen extends StatelessWidget {
  const OrgAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<OrdersCubit>()..loadOrders()),
        BlocProvider(create: (_) => sl<StorageOrdersCubit>()..loadOrders()),
        BlocProvider(create: (_) => sl<ManagerPendingUsersCubit>()..load()),
        BlocProvider.value(value: sl<NotificationsBadgeCubit>()),
        BlocProvider.value(value: sl<ChatBadgeCubit>()),
        BlocProvider(create: (_) => sl<ChatThreadsCubit>()..loadThreads()),
      ],
      child: const _OrgAdminHomeView(),
    );
  }
}

class _OrgAdminHomeView extends StatefulWidget {
  const _OrgAdminHomeView();

  @override
  State<_OrgAdminHomeView> createState() => _OrgAdminHomeViewState();
}

class _OrgAdminHomeViewState extends State<_OrgAdminHomeView> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_navIndex) {
        0 => const _OrdersTab(),
        1 => const InventoryManagementScreen(),
        2 => const _StorageCheckTab(),
        3 => const ChatHubSection(),
        4 => const _UsersTab(),
        _ => _SettingsTab(onLogout: () => context.read<AuthCubit>().signOut()),
      },
      floatingActionButton: _navIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateOrder(context),
              icon: const Icon(Icons.add),
              label: const Text('طلب جديد'),
            )
          : null,
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
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'فحص المخزن',
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
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'المستخدمون',
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

  void _openCreateOrder(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<CreateOrderCubit>()..loadLookups(),
          child: const CreateOrderScreen(),
        ),
      ),
    );
    if (result == true && context.mounted) {
      context.read<OrdersCubit>().loadOrders();
    }
  }
}

// ── Orders Tab (all orders, org-wide — same scope as verifier) ────────────────

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('لوحة المدير العام'),
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
          onPressed: () => context.read<OrdersCubit>().loadOrders(),
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
      body: BlocBuilder<OrdersCubit, OrdersState>(
        builder: (context, state) {
          if (state is OrdersLoading || state is OrdersInitial) {
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
          if (state is OrdersError) {
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
                                context.read<OrdersCubit>().loadOrders(),
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
          if (state is OrdersLoaded) {
            const doneStatuses = {
              OrderStatus.delivered,
              OrderStatus.deliveredToStorage,
            };
            final active = state.orders
                .where((o) => !doneStatuses.contains(o.status))
                .toList();
            final completed = state.orders
                .where((o) => doneStatuses.contains(o.status))
                .toList();
            return TabBarView(
              controller: _tabController,
              children: [
                _OrderList(
                  orders: active,
                  emptyMessage: 'لا توجد طلبات نشطة',
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  onSortModeChanged: (mode) =>
                      setState(() => _sortMode = mode),
                  directionFilter: _directionFilter,
                  onDirectionFilterChanged: (filter) =>
                      setState(() => _directionFilter = filter),
                  viewMode: _viewMode,
                  onViewModeChanged: (mode) =>
                      setState(() => _viewMode = mode),
                ),
                _OrderList(
                  orders: completed,
                  emptyMessage: 'لا توجد طلبات مكتملة',
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  onSortModeChanged: (mode) =>
                      setState(() => _sortMode = mode),
                  directionFilter: _directionFilter,
                  onDirectionFilterChanged: (filter) =>
                      setState(() => _directionFilter = filter),
                  viewMode: _viewMode,
                  onViewModeChanged: (mode) =>
                      setState(() => _viewMode = mode),
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
  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final filtered = prepareOrders(
      orders,
      searchQuery: searchQuery,
      directionFilter: directionFilter,
    );
    final visible = sortOrders(filtered, sortMode);

    return Builder(
      builder: (ctx) => RefreshIndicator(
        onRefresh: () => context.read<OrdersCubit>().loadOrders(),
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
                groupByEntity: false,
                onGroupByEntityChanged: (_) {},
                groupByRep: false,
                onGroupByRepChanged: (_) {},
                searchHint: 'بحث بالجهة أو المندوب...',
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(emptyMessage)),
              )
            else if (viewMode == OrderViewMode.grid)
              OrdersGridSliver(
                orders: visible,
                orderBuilder: (_, order) => OrderGridCard(
                  order: order,
                  onTap: () => _openOrder(context, order),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => OrderListTile(
                    order: visible[i],
                    onTap: () => _openOrder(context, visible[i]),
                  ),
                  childCount: visible.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOrder(BuildContext context, Order order) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          orderId: order.id,
          showDeleteButton: true,
          useVerifierRepository: true,
        ),
      ),
    );
    if ((deleted ?? false) && context.mounted) {
      context.read<OrdersCubit>().loadOrders();
    }
  }
}

// ── Storage check-items tab (assigned/picked_up orders needing storage
// action — same status-based scope as storage_actor, no ownership filter) ────

class _StorageCheckTab extends StatelessWidget {
  const _StorageCheckTab();

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('فحص طلبات المخزن'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<StorageOrdersCubit>().loadOrders(),
          tooltip: 'تحديث',
        ),
      ],
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
                    child: Center(child: Text(state.message)),
                  ),
                ],
              ),
            );
          }
          if (state is StorageOrdersLoaded) {
            if (state.activeOrders.isEmpty) {
              return Builder(
                builder: (ctx) => const CollapsingInnerScrollBody(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('لا توجد طلبات تحتاج إجراء')),
                    ),
                  ],
                ),
              );
            }
            return Builder(
              builder: (ctx) => RefreshIndicator(
                onRefresh: () => context.read<StorageOrdersCubit>().loadOrders(),
                child: CollapsingInnerScrollBody(
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => OrderListTile(
                          order: state.activeOrders[i],
                          onTap: () =>
                              _openDetail(context, state.activeOrders[i].id),
                        ),
                        childCount: state.activeOrders.length,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return const SizedBox.shrink();
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

// ── Users Tab (manager's pending approvals + all-users-by-role) ──────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
      title: const Text('المستخدمون'),
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
      sliverBottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'طلبات الانضمام'),
          Tab(text: 'المستخدمون'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Builder(
            builder: (ctx) => CollapsingInnerScrollBody(
              slivers: const [
                SliverFillRemaining(child: ManagerPendingUsersScreen()),
              ],
            ),
          ),
          Builder(
            builder: (ctx) => CollapsingInnerScrollBody(
              slivers: const [SliverFillRemaining(child: _AllUsersTab())],
            ),
          ),
        ],
      ),
    );
  }
}

class _AllUsersTab extends StatefulWidget {
  const _AllUsersTab();

  @override
  State<_AllUsersTab> createState() => _AllUsersTabState();
}

class _AllUsersTabState extends State<_AllUsersTab> {
  String _role = 'rep';
  late final UserTypeCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = sl<UserTypeCubit>()..load(_role);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'rep', label: Text('مناديب')),
                  ButtonSegment(
                      value: 'storage_actor', label: Text('أمناء المخزن')),
                  ButtonSegment(value: 'verifier', label: Text('مشرفون')),
                  ButtonSegment(value: 'manager', label: Text('مديرون')),
                  ButtonSegment(
                      value: 'admin', label: Text('مديرون عامون')),
                ],
                selected: {_role},
                onSelectionChanged: (s) {
                  setState(() => _role = s.first);
                  _cubit.load(s.first);
                },
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<UserTypeCubit, UserTypeState>(
              builder: (context, state) {
                if (state is UserTypeLoading || state is UserTypeInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is UserTypeError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _cubit.load(_role),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                if (state is UserTypeLoaded) {
                  if (state.users.isEmpty) {
                    return const Center(
                        child: Text('لا يوجد مستخدمون في هذه الفئة'));
                  }
                  return ListView.builder(
                    itemCount: state.users.length,
                    itemBuilder: (_, i) {
                      final user = state.users[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(user.fullName[0])),
                          title: Text(user.fullName),
                          subtitle: Text(user.phone ?? 'لا يوجد رقم هاتف'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfileScreen(profile: user, isSelf: false),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings Tab ──────────────────────────────────────────────────────────────

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
                          builder: (_) =>
                              ProfileScreen(profile: state.profile),
                        ),
                      );
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('الإحصائيات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider(
                        create: (_) => sl<StatsCubit>(),
                        child: const StatsScreen(),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('إدارة الجهات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/entities'),
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
