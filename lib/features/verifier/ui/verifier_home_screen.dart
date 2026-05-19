import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../chat/logic/chat_threads_cubit.dart';
import '../../chat/logic/order_chat_badge_cubit.dart';
import '../../chat/ui/chat_hub_screen.dart';
import '../../profile/ui/profile_screen.dart';
import '../../notifications/logic/chat_badge_cubit.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../../inventory/ui/inventory_availability_screen.dart';
import '../../manager/logic/stats_cubit.dart';
import '../../manager/ui/rep_list_screen.dart';
import '../../manager/ui/stats_screen.dart';
import '../../manager/ui/task_detail_screen.dart';
import '../logic/create_order_cubit.dart';
import '../logic/orders_cubit.dart';
import '../logic/orders_state.dart';
import 'create_order_screen.dart';
import 'widgets/order_card.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_sort_filter_bar.dart';

class VerifierHomeScreen extends StatelessWidget {
  const VerifierHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<OrdersCubit>()..loadOrders(),
      child: const _VerifierHomeView(),
    );
  }
}

class _VerifierHomeView extends StatefulWidget {
  const _VerifierHomeView();

  @override
  State<_VerifierHomeView> createState() => _VerifierHomeViewState();
}

class _VerifierHomeViewState extends State<_VerifierHomeView> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    sl<OrderChatBadgeCubit>().subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<OrderChatBadgeCubit>()),
        BlocProvider.value(value: sl<NotificationsBadgeCubit>()),
        BlocProvider.value(value: sl<ChatBadgeCubit>()),
        BlocProvider(create: (_) => sl<StatsCubit>()),
        BlocProvider(create: (_) => sl<ChatThreadsCubit>()..loadThreads()),
      ],
      child: _ScaffoldBody(
        navIndex: _navIndex,
        onNavChanged: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

class _ScaffoldBody extends StatelessWidget {
  final int navIndex;
  final ValueChanged<int> onNavChanged;
  const _ScaffoldBody({required this.navIndex, required this.onNavChanged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (navIndex) {
        0 || 1 => IndexedStack(
            index: navIndex,
            children: const [_OrdersTab(), RepListScreen()],
          ),
        2 => CollapsingHeaderWrapper(
            title: const Text('المحادثات'),
            actions: [
              if (chatHubCanCreate(context))
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined),
                  tooltip: 'محادثة جديدة',
                  onPressed: () => chatHubCreateThread(context),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
                onPressed: () =>
                    context.read<ChatThreadsCubit>().loadThreads(),
              ),
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
            body: const ChatHubBody(),
          ),
        3 => const StatsScreen(),
        _ => _SettingsTab(
            onInventoryTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InventoryAvailabilityScreen(),
              ),
            ),
            onLogout: () => context.read<AuthCubit>().signOut(),
          ),
      },
      floatingActionButton: navIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateOrder(context),
              icon: const Icon(Icons.add),
              label: const Text('طلب جديد'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: onNavChanged,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'الطلبات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.delivery_dining_outlined),
            selectedIcon: Icon(Icons.delivery_dining),
            label: 'المناديب',
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
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'الإحصائيات',
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
  bool _groupByEntity = false;
  OrderSortMode _sortMode = OrderSortMode.mostRecent;
  OrderDirectionFilter _directionFilter = OrderDirectionFilter.all;

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
      title: const Text('لوحة تحكم المشرف'),
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
        BlocBuilder<OrdersCubit, OrdersState>(
          builder: (context, state) => IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<OrdersCubit>().loadOrders(),
            tooltip: 'تحديث',
          ),
        ),
      ],
      sliverBottom: _VerifierOrdersTabHeader(
        tabController: _tabController,
      ),
      body: BlocBuilder<OrdersCubit, OrdersState>(
        builder: (context, state) {
          if (state is OrdersLoading || state is OrdersInitial) {
            return Builder(
              builder: (ctx) => CollapsingInnerScrollBody(slivers: const [
                SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ]),
            );
          }
          if (state is OrdersError) {
            return Builder(
              builder: (ctx) => CollapsingInnerScrollBody(slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message,
                            style: const TextStyle(color: AppColors.error)),
                        SizedBox(height: AppSpacing.verticalMedium),
                        AppButton(
                          text: 'إعادة المحاولة',
                          onPressed: () =>
                              context.read<OrdersCubit>().loadOrders(),
                          variant: AppButtonVariant.elevated,
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
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
                ),
                _groupByEntity
                    ? _GroupedByEntityList(
                        orders: completed,
                        searchQuery: _searchQuery,
                        sortMode: _sortMode,
                        groupByEntity: _groupByEntity,
                        onSearchChanged: (q) =>
                            setState(() => _searchQuery = q),
                        onSortModeChanged: (mode) =>
                            setState(() => _sortMode = mode),
                        directionFilter: _directionFilter,
                        onDirectionFilterChanged: (filter) =>
                            setState(() => _directionFilter = filter),
                        onGroupByChanged: (value) =>
                            setState(() => _groupByEntity = value),
                      )
                    : _OrderList(
                        orders: completed,
                        emptyMessage: 'لا توجد طلبات مكتملة',
                        searchQuery: _searchQuery,
                        sortMode: _sortMode,
                        groupByEntity: _groupByEntity,
                        onSearchChanged: (q) =>
                            setState(() => _searchQuery = q),
                        onSortModeChanged: (mode) =>
                            setState(() => _sortMode = mode),
                        directionFilter: _directionFilter,
                        onDirectionFilterChanged: (filter) =>
                            setState(() => _directionFilter = filter),
                        onGroupByChanged: (value) =>
                            setState(() => _groupByEntity = value),
                      ),
              ],
            );
          }
          return Builder(
            builder: (ctx) => const CollapsingInnerScrollBody(slivers: [
              SliverFillRemaining(child: SizedBox.shrink()),
            ]),
          );
        },
      ),
    );
  }
}

// ── Header bottom: tabs only ──────────────────────────────────────────────────

class _VerifierOrdersTabHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final TabController tabController;

  const _VerifierOrdersTabHeader({
    required this.tabController,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: tabController,
      tabs: const [
        Tab(text: 'نشطة'),
        Tab(text: 'مكتملة'),
      ],
    );
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
  final bool? groupByEntity;
  final ValueChanged<bool>? onGroupByChanged;
  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    this.searchQuery = '',
    this.groupByEntity,
    this.onGroupByChanged,
  });

  @override
  Widget build(BuildContext context) {
    final visible = sortOrders(
      filterOrdersByDirection(
        filterOrdersByQuery(orders, searchQuery),
        directionFilter,
      ),
      sortMode,
    );

    return BlocBuilder<OrderChatBadgeCubit, OrderChatBadgeState>(
      builder: (context, badgeState) {
        final sortedOrders = List<Order>.from(visible);
        sortedOrders.sort((a, b) {
          final aHasUrgent =
              badgeState.urgentCountByOrderId.containsKey(a.id);
          final bHasUrgent =
              badgeState.urgentCountByOrderId.containsKey(b.id);
          if (aHasUrgent && !bHasUrgent) return -1;
          if (!aHasUrgent && bHasUrgent) return 1;
          return 0;
        });

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
                    groupByEntity: groupByEntity,
                    onGroupByEntityChanged: onGroupByChanged,
                    searchHint: 'بحث بالجهة أو المندوب...',
                  ),
                ),
                if (sortedOrders.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(emptyMessage)),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final order = sortedOrders[i];
                        final hasUrgent =
                            order.status != OrderStatus.delivered &&
                                badgeState.urgentCountByOrderId
                                    .containsKey(order.id);
                        return Stack(
                          children: [
                            OrderCard(
                              order: order,
                              onTap: () async {
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
                              },
                            ),
                            if (hasUrgent)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: _UrgentBadge(),
                              ),
                          ],
                        );
                      },
                      childCount: sortedOrders.length,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UrgentBadge extends StatelessWidget {
  const _UrgentBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.symmetric(
          horizontal: AppSpacing.horizontalSmall,
          vertical: AppSpacing.verticalXSmall),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
      ),
      child: Text(
        'عاجل',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GroupedByEntityList extends StatelessWidget {
  final List<Order> orders;
  final String searchQuery;
  final OrderSortMode sortMode;
  final bool groupByEntity;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<OrderSortMode> onSortModeChanged;
  final OrderDirectionFilter directionFilter;
  final ValueChanged<OrderDirectionFilter> onDirectionFilterChanged;
  final ValueChanged<bool> onGroupByChanged;

  const _GroupedByEntityList({
    required this.orders,
    required this.sortMode,
    required this.groupByEntity,
    required this.onSearchChanged,
    required this.onSortModeChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    required this.onGroupByChanged,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final filtered = sortOrders(
      filterOrdersByDirection(
        filterOrdersByQuery(orders, searchQuery),
        directionFilter,
      ),
      sortMode,
    );

    final grouped = <String, List<Order>>{};
    for (final order in filtered) {
      (grouped[order.entityId] ??= []).add(order);
    }
    final autoExpand = grouped.length == 1;
    final entityIds = grouped.keys.toList();

    return BlocBuilder<OrderChatBadgeCubit, OrderChatBadgeState>(
      builder: (context, badgeState) {
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
                    groupByEntity: groupByEntity,
                    onGroupByEntityChanged: onGroupByChanged,
                    searchHint: 'بحث بالجهة أو المندوب...',
                  ),
                ),
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('لا توجد طلبات مكتملة')),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final entityId = entityIds[i];
                        final entityOrders = grouped[entityId]!;
                        final entityName =
                            entityOrders.first.entity?.name ?? '—';
                        final count = entityOrders.length;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ExpansionTile(
                            initiallyExpanded: autoExpand,
                            title: Text(
                              entityName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(20),
                                border: Border.all(color: AppColors.primary),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count ${count == 1 ? 'طلب' : 'طلبات'}',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            children: entityOrders.map((order) {
                              return OrderCard(
                                order: order,
                                onTap: () async {
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
                                },
                              );
                            }).toList(),
                          ),
                        );
                      },
                      childCount: entityIds.length,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Settings tab ──────────────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final VoidCallback onInventoryTap;
  final VoidCallback onLogout;

  const _SettingsTab({
    required this.onInventoryTap,
    required this.onLogout,
  });

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
                AppListTile(
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
                  showDivider: true,
                ),
                AppListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('المخزون'),
                  onTap: onInventoryTap,
                  showDivider: true,
                ),
                AppListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('إدارة الجهات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/entities'),
                  showDivider: true,
                ),
                AppListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('الإعدادات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings'),
                  showDivider: true,
                ),
                AppListTile(
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
