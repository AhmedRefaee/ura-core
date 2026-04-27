import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../inventory/ui/inventory_management_screen.dart';
import '../logic/storage_order_detail_cubit.dart';
import '../logic/storage_orders_cubit.dart';
import 'storage_order_detail_screen.dart';

class StorageHomeScreen extends StatelessWidget {
  const StorageHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StorageOrdersCubit>()..loadOrders(),
      child: const _StorageHomeView(),
    );
  }
}

class _StorageHomeView extends StatelessWidget {
  const _StorageHomeView();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بوابة المخزن'),
          actions: [
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'إدارة المخزون',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InventoryManagementScreen(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'المحادثات',
              onPressed: () => context.push('/chat'),
            ),
            BlocBuilder<StorageOrdersCubit, StorageOrdersState>(
              builder: (context, state) => IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<StorageOrdersCubit>().loadOrders(),
                tooltip: 'تحديث',
              ),
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
        body: BlocBuilder<StorageOrdersCubit, StorageOrdersState>(
          builder: (context, state) {
            if (state is StorageOrdersLoading || state is StorageOrdersInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is StorageOrdersError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message,
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          context.read<StorageOrdersCubit>().loadOrders(),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              );
            }
            if (state is StorageOrdersLoaded) {
              return TabBarView(
                children: [
                  _OrderList(
                    orders: state.activeOrders,
                    emptyMessage: 'لا توجد طلبات تحتاج إجراء',
                    onRefresh: () =>
                        context.read<StorageOrdersCubit>().loadOrders(),
                    onTap: (id) => _openDetail(context, id),
                  ),
                  _OrderList(
                    orders: state.doneOrders,
                    emptyMessage: 'لا توجد طلبات مكتملة',
                    onRefresh: () =>
                        context.read<StorageOrdersCubit>().loadOrders(),
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

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final void Function(String orderId) onTap;

  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    required this.onRefresh,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
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
