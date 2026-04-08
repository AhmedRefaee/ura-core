import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../logic/storage_order_detail_cubit.dart';

class StorageOrderDetailScreen extends StatelessWidget {
  const StorageOrderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<StorageOrderDetailCubit, StorageOrderDetailState>(
      listener: (context, state) {
        if (state is StorageOrderDetailError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          context.read<StorageOrderDetailCubit>().load();
        }
      },
      builder: (context, state) {
        if (state is StorageOrderDetailInitial ||
            state is StorageOrderDetailLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! StorageOrderDetailLoaded) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل الطلب')),
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    context.read<StorageOrderDetailCubit>().load(),
                child: const Text('إعادة المحاولة'),
              ),
            ),
          );
        }

        final order = state.order;
        return Scaffold(
          appBar: AppBar(
            title: Text(order.entity?.name ?? 'تفاصيل الطلب'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    context.read<StorageOrderDetailCubit>().load(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(order: order),
              const SizedBox(height: 16),
              _ItemsSection(state: state),
              const SizedBox(height: 24),
              _ApproveSection(state: state),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final dynamic order;
  const _InfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(Icons.business, 'الجهة', order.entity?.name ?? '—'),
            _InfoRow(Icons.swap_horiz, 'الاتجاه', order.directionLabel),
            if (order.rep != null)
              _InfoRow(Icons.person_outline, 'المندوب', order.rep!.fullName),
            if (order.notes != null && order.notes!.isNotEmpty)
              _InfoRow(Icons.notes, 'ملاحظات', order.notes!),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Items Section ────────────────────────────────────────────────────────────

class _ItemsSection extends StatelessWidget {
  final StorageOrderDetailLoaded state;
  const _ItemsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.order.items.isEmpty) {
      return const Text('لا توجد أصناف في هذا الطلب',
          style: TextStyle(color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الأصناف (${state.order.items.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...state.order.items.map(
          (item) => _CheckItemTile(
            item: item,
            effectiveStatus: state.effectiveStatus(item),
            isApproving: state.isApproving,
          ),
        ),
      ],
    );
  }
}

class _CheckItemTile extends StatelessWidget {
  final OrderItem item;
  final ItemCheckStatus effectiveStatus;
  final bool isApproving;

  const _CheckItemTile({
    required this.item,
    required this.effectiveStatus,
    required this.isApproving,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          item.isCustom
              ? Icons.shopping_bag_outlined
              : Icons.inventory_outlined,
          color: item.isCustom ? Colors.orange : Colors.teal,
        ),
        title: Text(item.displayName),
        subtitle: Text('الكمية: ${item.quantity}'),
        trailing: _ItemCheckControls(
          status: effectiveStatus,
          isApproving: isApproving,
          onCheck: () => context
              .read<StorageOrderDetailCubit>()
              .checkItem(item.id, ItemCheckStatus.checked),
          onReject: () => context
              .read<StorageOrderDetailCubit>()
              .checkItem(item.id, ItemCheckStatus.rejected),
          onRevert: () => context
              .read<StorageOrderDetailCubit>()
              .checkItem(item.id, ItemCheckStatus.pending),
        ),
      ),
    );
  }
}

class _ItemCheckControls extends StatelessWidget {
  final ItemCheckStatus status;
  final bool isApproving;
  final VoidCallback onCheck;
  final VoidCallback onReject;
  final VoidCallback onRevert;

  const _ItemCheckControls({
    required this.status,
    required this.isApproving,
    required this.onCheck,
    required this.onReject,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    if (isApproving) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (status) {
      case ItemCheckStatus.pending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
              tooltip: 'مطابق',
              onPressed: onCheck,
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              tooltip: 'مرفوض',
              onPressed: onReject,
            ),
          ],
        );
      case ItemCheckStatus.checked:
        return IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.green),
          tooltip: 'مطابق — اضغط للتراجع',
          onPressed: onRevert,
        );
      case ItemCheckStatus.rejected:
        return IconButton(
          icon: const Icon(Icons.cancel, color: Colors.red),
          tooltip: 'مرفوض — اضغط للتراجع',
          onPressed: onRevert,
        );
    }
  }
}

// ─── Approve Section ──────────────────────────────────────────────────────────

class _ApproveSection extends StatelessWidget {
  final StorageOrderDetailLoaded state;
  const _ApproveSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final approved = state.order.status == OrderStatus.pickedUp ||
        state.order.status == OrderStatus.onTheMove ||
        state.order.status == OrderStatus.delivered;

    if (approved) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('تمت الموافقة على هذا الطلب',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!state.canApprove && !state.isApproving)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'يجب مراجعة جميع الأصناف (مطابق أو مرفوض) قبل الموافقة',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        FilledButton.icon(
          onPressed: state.canApprove
              ? () => context.read<StorageOrderDetailCubit>().approveOrder()
              : null,
          icon: state.isApproving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.verified_outlined),
          label: const Text('موافقة على الطلب'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }
}
