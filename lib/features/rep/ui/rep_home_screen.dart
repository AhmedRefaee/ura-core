import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../inventory/ui/inventory_availability_screen.dart';
import '../logic/rep_order_detail_cubit.dart';
import '../logic/rep_orders_cubit.dart';
import 'rep_order_detail_screen.dart';

class RepHomeScreen extends StatelessWidget {
  const RepHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<RepOrdersCubit>()..loadOrders(),
      child: const _RepHomeView(),
    );
  }
}

class _RepHomeView extends StatelessWidget {
  const _RepHomeView();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مهامي'),
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
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<RepOrdersCubit>().loadOrders(),
              tooltip: 'تحديث',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => context.read<AuthCubit>().signOut(),
              tooltip: 'تسجيل الخروج',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'نشطة'),
              Tab(text: 'مكتملة'),
            ],
          ),
        ),
        body: BlocBuilder<RepOrdersCubit, RepOrdersState>(
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
              final active = state.orders
                  .where((o) => o.status != OrderStatus.delivered &&
                              o.status != OrderStatus.deliveredToStorage)
                  .toList();
              final completed = state.orders
                  .where((o) => o.status == OrderStatus.delivered ||
                              o.status == OrderStatus.deliveredToStorage)
                  .toList();
              return TabBarView(
                children: [
                  _RepOrderList(
                    orders: active,
                    emptyMessage: 'لا توجد مهام معينة لك حالياً',
                    onTap: (id) => _openDetail(context, id),
                  ),
                  _RepOrderList(
                    orders: completed,
                    emptyMessage: 'لا توجد مهام مكتملة',
                    onTap: (id) => _openDetail(context, id),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
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
    if (orders.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<RepOrdersCubit>().loadOrders(),
      child: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (_, i) => OrderListTile(
          order: orders[i],
          onTap: () => onTap(orders[i].id),
        ),
      ),
    );
  }
}
