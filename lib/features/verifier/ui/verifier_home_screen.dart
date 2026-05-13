import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
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
      appBar: AppBar(
        title: Text(navIndex == 2 ? 'المحادثات' : 'لوحة تحكم المشرف'),
        actions: [
          BlocBuilder<NotificationsBadgeCubit, int>(
            builder: (context, count) => Badge(
              isLabelVisible: count > 0,
              alignment: Alignment.topRight,
              offset: const Offset(-8, 8),
              label: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'الإشعارات',
                onPressed: () => context.push('/notifications'),
              ),
            ),
          ),
          if (navIndex == 0)
            BlocBuilder<OrdersCubit, OrdersState>(
              builder: (context, state) => IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<OrdersCubit>().loadOrders(),
                tooltip: 'تحديث',
              ),
            ),
          if (navIndex == 2) ...[
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
          ],
        ],
      ),
      body: switch (navIndex) {
        0 || 1 => IndexedStack(
            index: navIndex,
            children: const [_OrdersTab(), RepListScreen()],
          ),
        2 => const ChatHubBody(),
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
              builder: (context, count) => Badge(
                isLabelVisible: count > 0,
                alignment: Alignment.topRight,
                offset: const Offset(-8, 8),
                label: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                backgroundColor: AppColors.error,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            selectedIcon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => Badge(
                isLabelVisible: count > 0,
                alignment: Alignment.topRight,
                offset: const Offset(-8, 8),
                label: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                backgroundColor: AppColors.error,
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

class _OrdersTab extends StatelessWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'نشطة'),
              Tab(text: 'مكتملة'),
            ],
          ),
          Expanded(
            child: BlocBuilder<OrdersCubit, OrdersState>(
              builder: (context, state) {
                if (state is OrdersLoading || state is OrdersInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is OrdersError) {
                  return Center(
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
                    children: [
                      _OrderList(
                          orders: active,
                          emptyMessage: 'لا توجد طلبات نشطة'),
                      _OrderList(
                          orders: completed,
                          emptyMessage: 'لا توجد طلبات مكتملة'),
                    ],
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

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  const _OrderList({required this.orders, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<OrdersCubit>().loadOrders(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 400,
              child: Center(child: Text(emptyMessage)),
            ),
          ],
        ),
      );
    }

    return BlocBuilder<OrderChatBadgeCubit, OrderChatBadgeState>(
      builder: (context, badgeState) {
        final sortedOrders = List<Order>.from(orders);
        sortedOrders.sort((a, b) {
          final aHasUrgent =
              badgeState.urgentCountByOrderId.containsKey(a.id);
          final bHasUrgent =
              badgeState.urgentCountByOrderId.containsKey(b.id);
          if (aHasUrgent && !bHasUrgent) return -1;
          if (!aHasUrgent && bHasUrgent) return 1;
          return 0;
        });

        return RefreshIndicator(
          onRefresh: () => context.read<OrdersCubit>().loadOrders(),
          child: ListView.builder(
          itemCount: sortedOrders.length,
          itemBuilder: (context, i) {
            final order = sortedOrders[i];
            final hasUrgent = order.status != OrderStatus.delivered &&
                badgeState.urgentCountByOrderId.containsKey(order.id);
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
      padding: AppSpacing.symmetric(horizontal: AppSpacing.horizontalSmall, vertical: AppSpacing.verticalXSmall),
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

class _SettingsTab extends StatelessWidget {
  final VoidCallback onInventoryTap;
  final VoidCallback onLogout;

  const _SettingsTab({
    required this.onInventoryTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.allLarge,
      children: [
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
                  builder: (_) => ProfileScreen(profile: state.profile),
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
      ],
    );
  }
}
