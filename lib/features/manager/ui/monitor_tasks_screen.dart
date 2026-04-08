import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/order.dart';
import '../logic/monitor_orders_cubit.dart';
import 'task_detail_screen.dart';

class MonitorTasksScreen extends StatelessWidget {
  const MonitorTasksScreen({super.key});

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
            child: BlocBuilder<MonitorOrdersCubit, MonitorOrdersState>(
              builder: (context, state) {
                if (state is MonitorOrdersLoading || state is MonitorOrdersInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is MonitorOrdersError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              context.read<MonitorOrdersCubit>().load(),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                if (state is MonitorOrdersLoaded) {
                  return TabBarView(
                    children: [
                      _OrderList(
                        orders: state.activeOrders,
                        emptyMessage: 'لا توجد مهام نشطة',
                      ),
                      _OrderList(
                        orders: state.finishedOrders,
                        emptyMessage: 'لا توجد مهام مكتملة',
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

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  const _OrderList({required this.orders, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return Center(child: Text(emptyMessage));
    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (_, i) => _TaskCard(order: orders[i]),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Order order;
  const _TaskCard({required this.order});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    switch (order.status) {
      case OrderStatus.assigned:
        statusColor = Colors.orange;
        statusIcon = Icons.assignment_outlined;
      case OrderStatus.pickedUp:
        statusColor = Colors.blue;
        statusIcon = Icons.inventory_2_outlined;
      case OrderStatus.onTheMove:
        statusColor = Colors.purple;
        statusIcon = Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(orderId: order.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor),
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
                      '${order.directionLabel}  ·  ${order.items.length} أصناف'
                      '${order.rep != null ? "  ·  ${order.rep!.fullName}" : ""}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  border: Border.all(color: statusColor),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.statusLabel,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
