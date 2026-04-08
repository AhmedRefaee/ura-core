import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.fullName),
            Text(_roleLabel(user.role),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<UserOrdersCubit>().loadForUser(user),
          ),
        ],
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
            if (state.orders.isEmpty) {
              return const Center(child: Text('لا توجد مهام مرتبطة بهذا المستخدم'));
            }
            return ListView.builder(
              itemCount: state.orders.length,
              itemBuilder: (_, i) => _OrderCard(
                order: state.orders[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(orderId: state.orders[i].id),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

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
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                      '${order.directionLabel}  ·  ${order.items.length} أصناف',
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
