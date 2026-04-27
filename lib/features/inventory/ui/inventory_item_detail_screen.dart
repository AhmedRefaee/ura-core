import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_audit_log_entry.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_detail_cubit.dart';
import 'inventory_form_screen.dart';
import 'widgets/availability_badge.dart';

class InventoryItemDetailScreen extends StatelessWidget {
  final InventoryItem item;

  const InventoryItemDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl.get<InventoryDetailCubit>(param1: item.id)..load(),
      child: _InventoryItemDetailView(initialItem: item),
    );
  }
}

class _InventoryItemDetailView extends StatelessWidget {
  final InventoryItem initialItem;
  const _InventoryItemDetailView({required this.initialItem});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InventoryDetailCubit, InventoryDetailState>(
      listener: (context, state) {
        if (state is InventoryDetailSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          Navigator.pop(context);
        }
        if (state is InventoryDetailError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, state) {
        final item =
            state is InventoryDetailLoaded ? state.item : initialItem;
        final isActing =
            state is InventoryDetailLoaded && state.isActing;

        return Scaffold(
          appBar: AppBar(
            title: Text(item.itemName),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'تعديل',
                onPressed: isActing
                    ? null
                    : () => _openEdit(context, item),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'حذف',
                color: Colors.red,
                onPressed: isActing
                    ? null
                    : () => _confirmDelete(context),
              ),
            ],
          ),
          body: () {
            if (state is InventoryDetailLoading ||
                state is InventoryDetailInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is InventoryDetailLoaded) {
              return _DetailBody(state: state);
            }
            return const SizedBox.shrink();
          }(),
        );
      },
    );
  }

  void _openEdit(BuildContext context, InventoryItem item) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryFormScreen(initialItem: item),
      ),
    );
    if (updated == true && context.mounted) {
      context.read<InventoryDetailCubit>().load();
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الصنف؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<InventoryDetailCubit>().deleteItem();
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final InventoryDetailLoaded state;
  const _DetailBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final item = state.item;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Item info card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.itemName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AvailabilityBadge(status: item.availabilityStatus),
                  ],
                ),
                const Divider(height: 24),
                _InfoRow(label: 'الكمية', value: '${item.quantity} ${item.unit}'),
                if (item.sku != null)
                  _InfoRow(label: 'رمز SKU', value: item.sku!),
                if (item.category != null)
                  _InfoRow(label: 'الفئة', value: item.category!),
                _InfoRow(
                  label: 'حد التنبيه',
                  value: '${item.minQuantity} ${item.unit}',
                ),
                if (item.description != null &&
                    item.description!.isNotEmpty)
                  _InfoRow(label: 'الوصف', value: item.description!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Audit log section
        Text(
          'سجل التغييرات',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (state.auditLog.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا يوجد سجل تغييرات',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...state.auditLog.map((entry) => _AuditLogTile(entry: entry)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  final InventoryAuditLogEntry entry;
  const _AuditLogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final hasQuantityChange =
        entry.oldQuantity != null && entry.newQuantity != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.history, color: Colors.blueGrey),
        title: Text(entry.actionLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasQuantityChange)
              Text(
                '${entry.oldQuantity} → ${entry.newQuantity}',
                style: const TextStyle(fontSize: 13),
              ),
            if (entry.performer != null)
              Text(
                entry.performer!.fullName,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (entry.notes != null && entry.notes!.isNotEmpty)
              Text(
                entry.notes!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        trailing: entry.performedAt != null
            ? Text(
                _formatDate(entry.performedAt!),
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
              )
            : null,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }
}
