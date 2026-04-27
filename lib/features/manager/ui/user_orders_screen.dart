import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/widgets/order_list_tile.dart';
import '../logic/user_orders_cubit.dart';
import 'task_detail_screen.dart';

class UserOrdersScreen extends StatelessWidget {
  final Profile user;
  const UserOrdersScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<UserOrdersCubit>()..loadForUser(user),
      child: _UserOrdersView(user: user),
    );
  }
}

class _UserOrdersView extends StatelessWidget {
  final Profile user;
  const _UserOrdersView({required this.user});

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.rep:
        return 'مندوب';
      case UserRole.storageActor:
        return 'أمين مخزن';
      case UserRole.verifier:
        return 'مشرف';
      case UserRole.manager:
        return 'مدير';
      default:
        return '';
    }
  }

  bool get _hasTabs =>
      user.role == UserRole.storageActor || user.role == UserRole.rep;

  @override
  Widget build(BuildContext context) {
    // Reps and storage actors get a two-tab view (active/done); others get a flat list.
    if (_hasTabs) {
      return DefaultTabController(
        length: 2,
        child: _TabbedScaffold(user: user, roleLabel: _roleLabel(user.role)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.fullName),
            Text(_roleLabel(user.role),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<UserOrdersCubit>().loadForUser(user),
          ),
        ],
      ),
      body: BlocBuilder<UserOrdersCubit, UserOrdersState>(
        builder: (context, state) => _buildBody(context, state, null),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, UserOrdersState state, List<Order>? overrideList) {
    if (state is UserOrdersLoading || state is UserOrdersInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is UserOrdersError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.message, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  context.read<UserOrdersCubit>().loadForUser(user),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (state is UserOrdersLoaded) {
      final orders = overrideList ?? state.orders;
      if (orders.isEmpty) {
        return const Center(child: Text('لا توجد مهام مرتبطة بهذا المستخدم'));
      }
      return ListView.builder(
        itemCount: orders.length,
        itemBuilder: (_, i) => OrderListTile(
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
    return const SizedBox.shrink();
  }

  // ignore: unused_element
  Widget _buildBodyForTab(BuildContext context, List<Order> Function(UserOrdersLoaded) pick) {
    return BlocBuilder<UserOrdersCubit, UserOrdersState>(
      builder: (context, state) {
        if (state is UserOrdersLoaded) {
          return _buildBody(context, state, pick(state));
        }
        return _buildBody(context, state, null);
      },
    );
  }
}

class _TabbedScaffold extends StatelessWidget {
  final Profile user;
  final String roleLabel;
  const _TabbedScaffold(
      {required this.user, required this.roleLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.fullName),
            Text(roleLabel,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<UserOrdersCubit>().loadForUser(user),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'نشطة'),
            Tab(text: 'مكتملة'),
          ],
        ),
      ),
      body: BlocBuilder<UserOrdersCubit, UserOrdersState>(
        builder: (context, state) {
          if (state is UserOrdersLoading || state is UserOrdersInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is UserOrdersError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message,
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () =>
                        context.read<UserOrdersCubit>().loadForUser(user),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          if (state is UserOrdersLoaded) {
            return TabBarView(
              children: [
                _OrderList(orders: state.orders, emptyMessage: 'لا توجد طلبات نشطة'),
                _OrderList(orders: state.doneOrders, emptyMessage: 'لا توجد طلبات مكتملة'),
              ],
            );
          }
          return const SizedBox.shrink();
        },
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
      itemBuilder: (_, i) => OrderListTile(
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
