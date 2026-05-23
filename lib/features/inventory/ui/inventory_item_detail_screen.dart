import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
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
      create: (_) => sl.get<InventoryDetailCubit>(param1: item.id)..load(),
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
          AppSnackbar.show(
            context,
            message: state.message,
            variant: AppSnackbarVariant.success,
          );
          Navigator.pop(context);
        }
        if (state is InventoryDetailError) {
          AppSnackbar.show(
            context,
            message: state.message,
            variant: AppSnackbarVariant.error,
          );
        }
      },
      builder: (context, state) {
        final item = state is InventoryDetailLoaded ? state.item : initialItem;
        final isActing = state is InventoryDetailLoaded && state.isActing;

        return Scaffold(
          appBar: AppBar(
            title: Text(item.itemName),
            actions: [
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'تعديل',
                variant: AppIconButtonVariant.text,
                onPressed: isActing ? null : () => _openEdit(context, item),
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                tooltip: 'حذف',
                variant: AppIconButtonVariant.text,
                iconColor: AppColors.error,
                onPressed: isActing ? null : () => _confirmDelete(context),
              ),
            ],
          ),
          body: () {
            if (state is InventoryDetailLoading ||
                state is InventoryDetailInitial) {
              return const Center(child: AppLoadingIndicator());
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
      MaterialPageRoute(builder: (_) => InventoryFormScreen(initialItem: item)),
    );
    if (updated == true && context.mounted) {
      context.read<InventoryDetailCubit>().load();
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد الحذف', style: AppTextStyles.titleLarge),
        content: Text(
          'هل أنت متأكد من حذف هذا الصنف؟ لا يمكن التراجع عن هذا الإجراء.',
          style: AppTextStyles.bodyMedium,
        ),
        actionsPadding: EdgeInsets.fromLTRB(
          AppSpacing.horizontalLarge,
          0,
          AppSpacing.horizontalLarge,
          AppSpacing.verticalMedium,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    onPressed: () => Navigator.pop(ctx),
                    text: 'إلغاء',
                    variant: AppButtonVariant.outlined,
                    backgroundColor: AppColors.textSecondary,
                  ),
                ),
                SizedBox(width: AppSpacing.horizontalSmall),
                Expanded(
                  child: AppButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.read<InventoryDetailCubit>().deleteItem();
                    },
                    text: 'حذف',
                    backgroundColor: AppColors.error,
                  ),
                ),
              ],
            ),
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
      padding: AppSpacing.allMedium,
      children: [
        // Item info card
        Card(
          child: Padding(
            padding: AppSpacing.allMedium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.itemName,
                        style: AppTextStyles.titleLarge,
                      ),
                    ),
                    AvailabilityBadge(status: item.availabilityStatus),
                  ],
                ),
                Divider(height: AppSpacing.verticalXXLarge),
                _InfoRow(
                  label: 'الكمية',
                  value: '${item.quantity} ${item.unit}',
                ),
                if (item.sku != null)
                  _InfoRow(label: 'رمز SKU', value: item.sku!),
                if (item.category != null)
                  _InfoRow(label: 'الفئة', value: item.category!),
                _InfoRow(
                  label: 'حد التنبيه',
                  value: '${item.minQuantity} ${item.unit}',
                ),
                if (item.description != null && item.description!.isNotEmpty)
                  _InfoRow(label: 'الوصف', value: item.description!),
              ],
            ),
          ),
        ),
        SizedBox(height: AppSpacing.verticalLarge),
        // Audit log section
        Text(
          'سجل التغييرات',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: AppSpacing.verticalSmall),
        if (state.auditLog.isEmpty)
          Center(
            child: Padding(
              padding: AppSpacing.allMedium,
              child: Text(
                'لا يوجد سجل تغييرات',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
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
      padding: EdgeInsets.symmetric(vertical: AppSpacing.verticalXSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
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
      margin: EdgeInsets.symmetric(vertical: AppSpacing.verticalXSmall),
      child: ListTile(
        leading: Icon(Icons.history, color: AppColors.textSecondary),
        title: Text(
          entry.actionLabel,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasQuantityChange)
              Text(
                '${entry.oldQuantity} → ${entry.newQuantity}',
                style: AppTextStyles.bodySmall,
              ),
            if (entry.performer != null)
              Text(
                entry.performer!.fullName,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            if (entry.notes != null && entry.notes!.isNotEmpty)
              Text(
                entry.notes!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        trailing: entry.performedAt != null
            ? Text(
                _formatDate(entry.performedAt!),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            : null,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }
}
