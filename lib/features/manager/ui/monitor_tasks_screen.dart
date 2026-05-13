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
                      _FinishedOrderList(
                        orders: state.finishedOrders,
                        hasMore: state.hasMoreFinished,
                        isLoadingMore: state.isLoadingMoreFinished,
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
    return RefreshIndicator(
      onRefresh: () => context.read<MonitorOrdersCubit>().load(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: orders.isEmpty ? 1 : orders.length,
        itemBuilder: (context, i) {
          if (orders.isEmpty) {
            return SizedBox(
              height: 400,
              child: Center(child: Text(emptyMessage)),
            );
          }
          return OrderListTile(
            order: orders[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TaskDetailScreen(orderId: orders[i].id),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FinishedOrderList extends StatefulWidget {
  final List<Order> orders;
  final bool hasMore;
  final bool isLoadingMore;

  const _FinishedOrderList({
    required this.orders,
    required this.hasMore,
    required this.isLoadingMore,
  });

  @override
  State<_FinishedOrderList> createState() => _FinishedOrderListState();
}

class _FinishedOrderListState extends State<_FinishedOrderList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<MonitorOrdersCubit>().loadMoreFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    return RefreshIndicator(
      onRefresh: () => context.read<MonitorOrdersCubit>().load(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: orders.isEmpty ? 1 : orders.length + (widget.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (orders.isEmpty) {
            return const SizedBox(
              height: 400,
              child: Center(child: Text('لا توجد مهام مكتملة')),
            );
          }
          if (i == orders.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: widget.isLoadingMore
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : const SizedBox.shrink(),
            );
          }
          return OrderListTile(
            order: orders[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TaskDetailScreen(orderId: orders[i].id),
              ),
            ),
          );
        },
      ),
    );
  }
}
