import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/order_status_theme.dart';
import '../logic/rep_list_cubit.dart';
import 'user_orders_screen.dart';

/// Shared screen showing all reps with cards colored by their latest task status.
/// Used by both Verifier and Manager.
class RepListScreen extends StatelessWidget {
  const RepListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<RepListCubit>()..load(),
      child: const _RepListView(),
    );
  }
}

class _RepListView extends StatelessWidget {
  const _RepListView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المندوبون'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<RepListCubit>().load(),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: BlocBuilder<RepListCubit, RepListState>(
        builder: (context, state) {
          if (state is RepListLoading || state is RepListInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is RepListError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.read<RepListCubit>().load(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          if (state is RepListLoaded) {
            if (state.reps.isEmpty) {
              return const Center(child: Text('لا يوجد مندوبون مسجلون'));
            }
            return RefreshIndicator(
              onRefresh: () => context.read<RepListCubit>().load(),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: state.reps.length,
                itemBuilder: (_, i) => _RepCard(rep: state.reps[i]),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _RepCard extends StatelessWidget {
  final RepWithStatus rep;
  const _RepCard({required this.rep});

  @override
  Widget build(BuildContext context) {
    final status = rep.latestStatus;
    final cardColor = status?.color ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardColor.withAlpha(80), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserOrdersScreen(user: rep.profile),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cardColor.withAlpha(30),
                child: Icon(Icons.delivery_dining, color: cardColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rep.profile.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (rep.profile.phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        rep.profile.phone!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null)
                _StatusDot(status: status)
              else
                const Text(
                  'لا توجد مهام',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final OrderStatus status;
  const _StatusDot({required this.status});

  String get _label => switch (status) {
        OrderStatus.assigned || OrderStatus.pickedUp => 'قبل التنقل',
        OrderStatus.onTheMove => 'في الطريق',
        OrderStatus.delivered || OrderStatus.deliveredToStorage => 'مكتمل',
      };

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
