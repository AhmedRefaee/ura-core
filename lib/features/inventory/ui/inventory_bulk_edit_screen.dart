import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_bulk_cubit.dart';

class InventoryBulkEditScreen extends StatelessWidget {
  const InventoryBulkEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<InventoryBulkCubit>()..loadItems(),
      child: const _InventoryBulkEditView(),
    );
  }
}

class _InventoryBulkEditView extends StatelessWidget {
  const _InventoryBulkEditView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InventoryBulkCubit, InventoryBulkState>(
      listener: (context, state) {
        if (state is InventoryBulkSuccess) {
          Navigator.pop(context, true);
        }
        if (state is InventoryBulkError) {
          AppSnackbar.show(
            context,
            message: state.message,
            variant: AppSnackbarVariant.error,
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('تعديل الكميات'),
            actions: [
              if (state is InventoryBulkReady && state.hasChanges)
                Padding(
                  padding: EdgeInsets.only(left: AppSpacing.horizontalSmall),
                  child: Center(
                    child: Text(
                      '${state.pendingQuantities.length} تغيير',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: () {
            if (state is InventoryBulkLoading ||
                state is InventoryBulkInitial) {
              return const Center(child: AppLoadingIndicator());
            }
            if (state is InventoryBulkSaving) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppLoadingIndicator(),
                    SizedBox(height: AppSpacing.verticalMedium),
                    Text('جاري الحفظ...', style: AppTextStyles.bodyMedium),
                  ],
                ),
              );
            }
            if (state is InventoryBulkError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.message,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    AppButton(
                      onPressed: () =>
                          context.read<InventoryBulkCubit>().loadItems(),
                      text: 'إعادة المحاولة',
                    ),
                  ],
                ),
              );
            }
            if (state is InventoryBulkReady) {
              if (state.items.isEmpty) {
                return Center(
                    child: Text(
                      'لا توجد عناصر في المخزون',
                      style: AppTextStyles.bodyMedium,
                    ),
                  );
              }
              return ListView.builder(
                padding: EdgeInsets.only(bottom: AppSpacing.verticalXXXLarge),
                itemCount: state.items.length,
                itemBuilder: (_, i) =>
                    _BulkItemRow(item: state.items[i], state: state),
              );
            }
            return const SizedBox.shrink();
          }(),
          bottomNavigationBar: state is InventoryBulkReady
              ? _BottomBar(state: state)
              : null,
        );
      },
    );
  }
}

class _BulkItemRow extends StatefulWidget {
  final InventoryItem item;
  final InventoryBulkReady state;

  const _BulkItemRow({required this.item, required this.state});

  @override
  State<_BulkItemRow> createState() => _BulkItemRowState();
}

class _BulkItemRowState extends State<_BulkItemRow> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: '${widget.state.effectiveQuantity(widget.item)}',
    );
  }

  @override
  void didUpdateWidget(_BulkItemRow old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      final newVal = '${widget.state.effectiveQuantity(widget.item)}';
      if (_ctrl.text != newVal) _ctrl.text = newVal;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChanged =
        widget.state.pendingQuantities.containsKey(widget.item.id);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalMedium, vertical: AppSpacing.verticalXSmall),
      color: isChanged
          ? AppColors.primary.withAlpha(60)
          : null,
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.itemName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.item.category != null)
                    Text(
                      widget.item.category!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (isChanged)
              Padding(
                padding: EdgeInsets.only(left: AppSpacing.horizontalSmall),
                child: Text(
                  '(أصلي: ${widget.item.quantity})',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                      vertical: AppSpacing.verticalSmall, horizontal: AppSpacing.horizontalSmall),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                    borderSide: isChanged
                        ? BorderSide(
                            color: AppColors.primary,
                            width: 2)
                        : const BorderSide(),
                  ),
                  suffixText: widget.item.unit,
                ),
                onTap: () => setState(() => _editing = true),
                onChanged: (_) => setState(() {}),
                onSubmitted: _commit,
                onEditingComplete: () => _commit(_ctrl.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commit(String value) {
    setState(() => _editing = false);
    final qty = int.tryParse(value.trim());
    if (qty != null && qty >= 0) {
      context.read<InventoryBulkCubit>().setQuantity(widget.item.id, qty);
    } else {
      // revert to current effective quantity
      _ctrl.text = '${widget.state.effectiveQuantity(widget.item)}';
    }
  }
}

class _BottomBar extends StatelessWidget {
  final InventoryBulkReady state;
  const _BottomBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: AppSpacing.horizontalMediumPadding.copyWith(
          top: AppSpacing.verticalSmall,
          bottom: AppSpacing.verticalMedium,
        ),
        child: AppButton(
          onPressed: state.hasChanges
              ? () => context.read<InventoryBulkCubit>().saveChanges()
              : null,
          text: state.hasChanges
                ? 'حفظ ${state.pendingQuantities.length} تغيير'
                : 'لا توجد تغييرات',
          icon: Icons.save_outlined,
        ),
      ),
    );
  }
}
