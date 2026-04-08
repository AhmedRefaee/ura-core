import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../auth/logic/auth_cubit.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('مهامي'),
        actions: [
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
            if (state.orders.isEmpty) {
              return const Center(
                child: Text('لا توجد مهام معينة لك حالياً'),
              );
            }
            return RefreshIndicator(
              onRefresh: () => context.read<RepOrdersCubit>().loadOrders(),
              child: ListView.builder(
                itemCount: state.orders.length,
                itemBuilder: (_, i) => _RepOrderCard(
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

class _RepOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  const _RepOrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statusIcon(order.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.entity?.name ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  _StatusBadge(order.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.category_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${order.items.length} أصناف',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 16),
                  const Icon(Icons.swap_horiz, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(order.directionLabel,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
              if (order.notes != null && order.notes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  order.notes!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(OrderStatus status) {
    IconData icon;
    Color color;
    switch (status) {
      case OrderStatus.assigned:
        icon = Icons.assignment_outlined;
        color = Colors.orange;
      case OrderStatus.pickedUp:
        icon = Icons.inventory_2_outlined;
        color = Colors.blue;
      case OrderStatus.onTheMove:
        icon = Icons.local_shipping_outlined;
        color = Colors.purple;
      case OrderStatus.delivered:
        icon = Icons.check_circle_outline;
        color = Colors.green;
    }
    return Icon(icon, color: color);
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (status) {
      case OrderStatus.assigned:
        bg = Colors.orange;
        label = 'معين';
      case OrderStatus.pickedUp:
        bg = Colors.blue;
        label = 'تم الاستلام';
      case OrderStatus.onTheMove:
        bg = Colors.purple;
        label = 'في الطريق';
      case OrderStatus.delivered:
        bg = Colors.green;
        label = 'مُسلَّم';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withAlpha(30),
        border: Border.all(color: bg),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: bg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
