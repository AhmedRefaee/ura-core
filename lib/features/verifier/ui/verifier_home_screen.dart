import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../auth/logic/auth_cubit.dart';
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

class _VerifierHomeView extends StatelessWidget {
  const _VerifierHomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المشرف'),
        actions: [
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
      body: const _OrdersTab(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrder(context),
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
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
                  final active = state.orders
                      .where((o) => o.status != OrderStatus.delivered)
                      .toList();
                  final completed = state.orders
                      .where((o) => o.status == OrderStatus.delivered)
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
    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (_, i) => OrderCard(order: orders[i]),
    );
  }
}
