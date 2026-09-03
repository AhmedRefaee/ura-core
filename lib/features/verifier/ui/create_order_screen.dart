import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/direction_selector.dart';
import '../../../shared/widgets/draft_order_items_list.dart';
import '../../../shared/widgets/entity_picker.dart';
import '../../../shared/widgets/rep_picker.dart';
import '../logic/create_order_cubit.dart';
import 'widgets/add_item_sheet.dart';
import 'widgets/templates_sheet.dart';
import '../../../core/design_system/theme/theme.dart';

class CreateOrderScreen extends StatefulWidget {
  final Order? prefillFrom;
  const CreateOrderScreen({super.key, this.prefillFrom});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  bool _prefilled = false;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CreateOrderCubit, CreateOrderState>(
      listener: (context, state) {
        if (state is CreateOrderReady &&
            !_prefilled &&
            widget.prefillFrom != null) {
          _prefilled = true;
          context.read<CreateOrderCubit>().applyCopyFromOrder(
            widget.prefillFrom!,
          );
        }
        if (state is CreateOrderSuccess) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم إنشاء الطلب بنجاح')));
          Navigator.pop(context, true);
        }
        if (state is CreateOrderError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        if (state is CreateOrderReady && state.templateSaveSucceeded) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم حفظ القالب بنجاح')));
        }
      },
      builder: (context, state) {
        if (state is CreateOrderInitial || state is CreateOrderLoadingLookups) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is CreateOrderError) {
          return Scaffold(
            appBar: AppBar(title: const Text('طلب جديد')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  SizedBox(height: AppSpacing.verticalMedium),
                  FilledButton(
                    onPressed: () =>
                        context.read<CreateOrderCubit>().loadLookups(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final ready = state is CreateOrderReady ? state : null;
        final isSubmitting = state is CreateOrderSubmitting;

        return Scaffold(
          appBar: AppBar(
            title: const Text('طلب جديد'),
            actions: [
              if (ready != null && ready.canSubmit)
                IconButton(
                  tooltip: 'حفظ كقالب',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () =>
                      context.read<CreateOrderCubit>().saveAsTemplate(),
                ),
            ],
          ),
          body: ready == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: AppSpacing.allLarge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Direction
                      _SectionTitle('اتجاه الطلب'),
                      DirectionSelector(
                        selected: ready.direction,
                        onChanged: (d) =>
                            context.read<CreateOrderCubit>().setDirection(d),
                      ),
                      SizedBox(height: AppSpacing.verticalXLarge),

                      // Entity
                      _SectionTitle(
                        ready.direction == OrderDirection.outbound
                            ? 'العميل'
                            : 'المورد',
                      ),
                      EntityPicker(
                        entities: ready.entities,
                        selected: ready.selectedEntity,
                        initialCategory: ready.direction.defaultEntityCategory,
                        onChanged: (e) =>
                            context.read<CreateOrderCubit>().selectEntity(e),
                      ),
                      SizedBox(height: AppSpacing.verticalXLarge),

                      // Rep (not for inbound_external)
                      if (ready.direction !=
                          OrderDirection.inboundExternal) ...[
                        _SectionTitle('المندوب'),
                        RepPicker(
                          reps: ready.reps,
                          repLatestStatuses: ready.repLatestStatuses,
                          selected: ready.selectedRep,
                          onChanged: (r) =>
                              context.read<CreateOrderCubit>().selectRep(r),
                        ),
                        SizedBox(height: AppSpacing.verticalXLarge),
                      ],

                      // Items
                      Row(
                        children: [
                          _SectionTitle('الأصناف'),
                          const Spacer(),
                          if (ready.selectedEntity != null)
                            TextButton.icon(
                              onPressed: () =>
                                  _showTemplatesSheet(context, ready),
                              icon: const Icon(Icons.flash_on, size: 18),
                              label: const Text('قالب'),
                            ),
                          TextButton.icon(
                            onPressed: () => _showAddItemDialog(context, ready),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      DraftOrderItemsList(
                        items: ready.items,
                        inventory: ready.inventory,
                        direction: ready.direction,
                        onRemove: (i) =>
                            context.read<CreateOrderCubit>().removeItem(i),
                        onEditCustom: (i) =>
                            _showEditCustomItemDialog(context, ready, i),
                      ),
                      SizedBox(height: AppSpacing.verticalXLarge),

                      // Notes
                      _SectionTitle('ملاحظات (اختياري)'),
                      TextField(
                        maxLines: 2,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'أي تعليمات أو ملاحظات...',
                        ),
                        onChanged: (v) =>
                            context.read<CreateOrderCubit>().setNotes(v),
                      ),
                      SizedBox(height: AppSpacing.verticalXXXLarge),

                      FilledButton(
                        onPressed: isSubmitting || !ready.canSubmit
                            ? null
                            : () => context.read<CreateOrderCubit>().submit(),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('إنشاء الطلب'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _showAddItemDialog(BuildContext context, CreateOrderReady state) {
    final cubit = context.read<CreateOrderCubit>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemSheet(
          inventory: state.inventory,
          orderDirection: state.direction,
          onAddInventoryItems: (items) => cubit.addMultipleItems(items),
          onAddCustomItem: (desc, qty, {sourceInventoryId}) => cubit
              .addCustomItem(desc, qty, sourceInventoryId: sourceInventoryId),
        ),
      ),
    );
  }

  void _showEditCustomItemDialog(
    BuildContext context,
    CreateOrderReady state,
    int index,
  ) {
    final cubit = context.read<CreateOrderCubit>();
    final item = state.items[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemSheet(
          inventory: state.inventory,
          orderDirection: state.direction,
          initialCustomJson: item.customDescription,
          onUpdateCustomItem: (desc, qty) =>
              cubit.updateCustomItem(index, desc, qty),
          // Unreachable in edit mode, but the sheet requires them.
          onAddInventoryItems: (items) => cubit.addMultipleItems(items),
          onAddCustomItem: (desc, qty, {sourceInventoryId}) => cubit
              .addCustomItem(desc, qty, sourceInventoryId: sourceInventoryId),
        ),
      ),
    );
  }

  void _showTemplatesSheet(BuildContext context, CreateOrderReady state) {
    final cubit = context.read<CreateOrderCubit>();
    showTemplatesSheet(
      context: context,
      entityId: state.selectedEntity!.id,
      entityName: state.selectedEntity!.name,
      onApply: (template) => cubit.applyTemplate(template),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}
