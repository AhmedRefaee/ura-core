import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../auth/logic/auth_cubit.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة المخزن'),
        actions: [
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
            if (state.orders.isEmpty) {
              return const Center(
                child: Text('لا توجد طلبات معلقة في المخزن'),
              );
            }
            return RefreshIndicator(
              onRefresh: () =>
                  context.read<StorageOrdersCubit>().loadOrders(),
              child: ListView.builder(
                itemCount: state.orders.length,
                itemBuilder: (_, i) => _StorageOrderCard(
                  order: state.orders[i],
                  onTap: () => _openDetail(context, state.orders[i].id),
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

class _StorageOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  const _StorageOrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        order.items.where((i) => i.checkStatus == ItemCheckStatus.pending).length;
    final total = order.items.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.warehouse_outlined,
                  color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.entity?.name ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total أصناف · ${order.directionLabel}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    if (order.notes != null && order.notes!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        order.notes!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProgressBadge(
                  reviewed: total - pendingCount, total: total),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBadge extends StatelessWidget {
  final int reviewed;
  final int total;
  const _ProgressBadge({required this.reviewed, required this.total});

  @override
  Widget build(BuildContext context) {
    final done = reviewed == total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: done ? Colors.green.shade50 : Colors.orange.shade50,
        border: Border.all(color: done ? Colors.green : Colors.orange),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$reviewed/$total',
        style: TextStyle(
          color: done ? Colors.green : Colors.orange,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
