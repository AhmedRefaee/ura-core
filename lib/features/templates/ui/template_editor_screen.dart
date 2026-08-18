import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/direction_selector.dart';
import '../../../shared/widgets/draft_order_items_list.dart';
import '../../../shared/widgets/entity_picker.dart';
import '../../../shared/widgets/rep_picker.dart';
import '../../verifier/ui/widgets/add_item_sheet.dart';
import '../logic/template_editor_cubit.dart';

class TemplateEditorScreen extends StatelessWidget {
  const TemplateEditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TemplateEditorCubit, TemplateEditorState>(
      listener: (context, state) {
        if (state is! TemplateEditorReady) return;
        if (state.justSaved || state.justDeleted) {
          Navigator.pop(context, true);
          return;
        }
        final error = state.actionError;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is TemplateEditorInitial ||
            state is TemplateEditorLoadingLookups) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is TemplateEditorLoadError) {
          return Scaffold(
            appBar: AppBar(title: const Text('القالب')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  SizedBox(height: AppSpacing.verticalMedium),
                  FilledButton(
                    onPressed: () =>
                        context.read<TemplateEditorCubit>().loadLookups(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final ready = state as TemplateEditorReady;
        final cubit = context.read<TemplateEditorCubit>();

        return Scaffold(
          appBar: AppBar(
            title: Text(ready.isNew ? 'قالب جديد' : 'تعديل القالب'),
            actions: [
              if (!ready.isNew)
                IconButton(
                  tooltip: 'حذف القالب',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: ready.isDeleting
                      ? null
                      : () => _confirmDelete(context, cubit),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: AppSpacing.allLarge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle('اسم القالب (اختياري)'),
                TextFormField(
                  initialValue: ready.name,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'مثلاً: طلب الأسبوع',
                  ),
                  onChanged: cubit.setName,
                ),
                SizedBox(height: AppSpacing.verticalXLarge),

                _SectionTitle('الوصف (اختياري)'),
                TextFormField(
                  initialValue: ready.description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'وصف مختصر للقالب...',
                  ),
                  onChanged: cubit.setDescription,
                ),
                SizedBox(height: AppSpacing.verticalXLarge),

                _SectionTitle('اتجاه الطلب'),
                DirectionSelector(
                  selected: ready.direction,
                  onChanged: cubit.setDirection,
                ),
                SizedBox(height: AppSpacing.verticalXLarge),

                _SectionTitle(
                  ready.direction == OrderDirection.outbound
                      ? 'العميل'
                      : 'المورد',
                ),
                // The entity is locked once a template exists: changing it
                // would move the template to a different entity's group.
                if (ready.isNew)
                  EntityPicker(
                    entities: ready.entities,
                    selected: ready.selectedEntity,
                    onChanged: cubit.selectEntity,
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.horizontalMedium,
                        vertical: AppSpacing.verticalLarge,
                      ),
                    ),
                    child: Text(ready.selectedEntity?.name ?? '—'),
                  ),
                SizedBox(height: AppSpacing.verticalXLarge),

                if (ready.direction != OrderDirection.inboundExternal) ...[
                  _SectionTitle('المندوب'),
                  RepPicker(
                    reps: ready.reps,
                    selected: ready.selectedRep,
                    onChanged: cubit.selectRep,
                  ),
                  SizedBox(height: AppSpacing.verticalXLarge),
                ],

                Row(
                  children: [
                    _SectionTitle('الأصناف'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showAddItemDialog(context, ready, cubit),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة'),
                    ),
                  ],
                ),
                DraftOrderItemsList(
                  items: ready.items,
                  inventory: ready.inventory,
                  direction: ready.direction,
                  onRemove: cubit.removeItem,
                ),
                SizedBox(height: AppSpacing.verticalXLarge),

                _SectionTitle('ملاحظات (اختياري)'),
                TextFormField(
                  initialValue: ready.notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'أي تعليمات أو ملاحظات...',
                  ),
                  onChanged: cubit.setNotes,
                ),
                SizedBox(height: AppSpacing.verticalXXXLarge),

                FilledButton(
                  onPressed: ready.isSaving || !ready.canSave
                      ? null
                      : () => cubit.save(),
                  child: ready.isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddItemDialog(
    BuildContext context,
    TemplateEditorReady state,
    TemplateEditorCubit cubit,
  ) {
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

  Future<void> _confirmDelete(
    BuildContext context,
    TemplateEditorCubit cubit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القالب'),
        content: const Text('هل تريد حذف هذا القالب؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) cubit.deleteExisting();
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
