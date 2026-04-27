import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../chat/logic/order_chat_badge_cubit.dart';
import '../../inventory/ui/inventory_availability_screen.dart';
import '../../manager/ui/rep_list_screen.dart';
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
    return BlocProvider.value(
      value: sl<OrderChatBadgeCubit>(),
      child: _ScaffoldBody(navIndex: _navIndex, onNavChanged: (i) => setState(() => _navIndex = i)),
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
        title: const Text('لوحة تحكم المشرف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'توافر المخزون',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InventoryAvailabilityScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'المحادثات',
            onPressed: () => context.push('/chat'),
          ),
          if (navIndex == 0)
            BlocBuilder<OrdersCubit, OrdersState>(
              builder: (context, state) => IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<OrdersCubit>().loadOrders(),
                tooltip: 'تحديث',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthCubit>().signOut(),
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: IndexedStack(
        index: navIndex,
        children: const [
          _OrdersTab(),
          RepListScreen(),
        ],
      ),
      floatingActionButton: navIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateOrder(context),
              icon: const Icon(Icons.add),
              label: const Text('طلب جديد'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) => onNavChanged(i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'الطلبات',
          ),
          NavigationDestination(
            icon: Icon(Icons.delivery_dining_outlined),
            selectedIcon: Icon(Icons.delivery_dining),
            label: 'المندوبون',
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
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              context.read<OrdersCubit>().loadOrders(),
                          child: const Text('إعادة المحاولة'),
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
                      _OrderList(orders: active, emptyMessage: 'لا توجد طلبات نشطة'),
                      _OrderList(orders: completed, emptyMessage: 'لا توجد طلبات مكتملة'),
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
      return Center(child: Text(emptyMessage));
    }

    return BlocBuilder<OrderChatBadgeCubit, OrderChatBadgeState>(
      builder: (context, badgeState) {
        final sortedOrders = List<Order>.from(orders);
        sortedOrders.sort((a, b) {
          final aHasUrgent = badgeState.urgentCountByOrderId.containsKey(a.id);
          final bHasUrgent = badgeState.urgentCountByOrderId.containsKey(b.id);
          if (aHasUrgent && !bHasUrgent) return -1;
          if (!aHasUrgent && bHasUrgent) return 1;
          return 0;
        });

        return ListView.builder(
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'عاجل',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
