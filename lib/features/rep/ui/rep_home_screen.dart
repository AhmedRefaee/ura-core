import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../chat/logic/chat_threads_cubit.dart';
import '../../chat/ui/chat_hub_screen.dart';
import '../../notifications/logic/chat_badge_cubit.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../../inventory/ui/inventory_availability_screen.dart';
import '../../profile/ui/profile_screen.dart';
import '../logic/rep_order_detail_cubit.dart';
import '../logic/rep_orders_cubit.dart';
import 'rep_order_detail_screen.dart';

class RepHomeScreen extends StatelessWidget {
  const RepHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<RepOrdersCubit>()..loadOrders()),
        BlocProvider.value(value: sl<NotificationsBadgeCubit>()),
        BlocProvider.value(value: sl<ChatBadgeCubit>()),
        BlocProvider(create: (_) => sl<ChatThreadsCubit>()..loadThreads()),
      ],
      child: const _RepHomeView(),
    );
  }
}

class _RepHomeView extends StatefulWidget {
  const _RepHomeView();

  @override
  State<_RepHomeView> createState() => _RepHomeViewState();
}

class _RepHomeViewState extends State<_RepHomeView> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _navIndex == 1
          ? null
          : AppBar(
              title: Text(_navIndex == 2 ? 'المحادثات' : 'مهامي'),
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
                if (_navIndex == 0)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () =>
                        context.read<RepOrdersCubit>().loadOrders(),
                    tooltip: 'تحديث',
                  ),
                if (_navIndex == 2)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث',
                    onPressed: () =>
                        context.read<ChatThreadsCubit>().loadThreads(),
                  ),
              ],
            ),
      body: switch (_navIndex) {
        0 => _OrdersTab(onOpenDetail: (id) => _openDetail(context, id)),
        1 => const InventoryAvailabilityScreen(),
        2 => const ChatHubBody(),
        3 => _SettingsTab(
            onLogout: () => context.read<AuthCubit>().signOut(),
          ),
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
              builder: (context, count) => Badge(
                isLabelVisible: count > 0,
                alignment: Alignment.topRight,
                offset: const Offset(-8, 8),
                label: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                backgroundColor: Colors.red,
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
                backgroundColor: Colors.red,
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

  void _openDetail(BuildContext context, String orderId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) =>
              sl.get<RepOrderDetailCubit>(param1: orderId)..load(),
          child: const RepOrderDetailScreen(),
        ),
      ),
    );
    if (context.mounted) {
      context.read<RepOrdersCubit>().loadOrders();
    }
  }
}

// ── Orders Tab (active + completed sub-tabs) ──────────────────────────────────

class _OrdersTab extends StatelessWidget {
  final void Function(String orderId) onOpenDetail;

  const _OrdersTab({required this.onOpenDetail});

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
            child: BlocBuilder<RepOrdersCubit, RepOrdersState>(
              builder: (context, state) {
                if (state is RepOrdersLoading || state is RepOrdersInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is RepOrdersError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              context.read<RepOrdersCubit>().loadOrders(),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                if (state is RepOrdersLoaded) {
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
                      _RepOrderList(
                        orders: active,
                        emptyMessage: 'لا توجد مهام معينة لك حالياً',
                        onTap: onOpenDetail,
                      ),
                      _RepOrderList(
                        orders: completed,
                        emptyMessage: 'لا توجد مهام مكتملة',
                        onTap: onOpenDetail,
                      ),
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

// ── Order list with pull-to-refresh ──────────────────────────────────────────

class _RepOrderList extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  final void Function(String orderId) onTap;

  const _RepOrderList({
    required this.orders,
    required this.emptyMessage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<RepOrdersCubit>().loadOrders(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: orders.isEmpty ? 1 : orders.length,
        itemBuilder: (_, i) {
          if (orders.isEmpty) {
            return SizedBox(
              height: 400,
              child: Center(child: Text(emptyMessage)),
            );
          }
          return OrderListTile(
            order: orders[i],
            onTap: () => onTap(orders[i].id),
          );
        },
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
      ],
    );
  }
}
