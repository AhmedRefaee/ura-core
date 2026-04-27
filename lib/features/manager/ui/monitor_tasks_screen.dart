import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/order_list_tile.dart';
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
      itemBuilder: (context, i) => OrderListTile(
        order: orders[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(orderId: orders[i].id),
          ),
        ),
      ),
    );
  }
}
