import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/models/order_template.dart';
import '../../logic/order_templates_cubit.dart';
import '../../../../core/design_system/theme/theme.dart';

/// Opens the templates sheet for [entityId] / [entityName].
/// [onApply] is called when the user taps a template.
void showTemplatesSheet({
  required BuildContext context,
  required String entityId,
  required String entityName,
  required void Function(OrderTemplate) onApply,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider(
      create: (_) => sl<OrderTemplatesCubit>()..load(entityId),
      child: _TemplatesSheetContent(
        entityName: entityName,
        onApply: onApply,
      ),
    ),
  );
}

class _TemplatesSheetContent extends StatelessWidget {
  final String entityName;
  final void Function(OrderTemplate) onApply;

  const _TemplatesSheetContent({
    required this.entityName,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: EdgeInsets.only(top: AppSpacing.verticalSmall),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.horizontalLarge, AppSpacing.verticalMedium, AppSpacing.horizontalLarge, AppSpacing.verticalXSmall),
              child: Row(
                children: [
                  const Icon(Icons.flash_on, size: 20),
                  SizedBox(width: AppSpacing.horizontalSmall),
                  Expanded(
                    child: Text(
                      'الطلبات المتكررة — $entityName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            // Body
            Expanded(
              child: BlocBuilder<OrderTemplatesCubit, OrderTemplatesState>(
                builder: (ctx, state) {
                  if (state is OrderTemplatesLoading ||
                      state is OrderTemplatesInitial) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is OrderTemplatesError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(state.message,
                              style: const TextStyle(color: Colors.red)),
                          SizedBox(height: AppSpacing.verticalSmall),
                          TextButton(
                            onPressed: () =>
                                ctx.read<OrderTemplatesCubit>().load(''),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    );
                  }
                  final templates = state is OrderTemplatesLoaded
                      ? state.templates
                      : <OrderTemplate>[];
                  if (templates.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_border,
                              size: 48, color: Colors.grey),
                          SizedBox(height: AppSpacing.verticalSmall),
                          Text(
                            'لا توجد قوالب محفوظة',
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: AppSpacing.verticalXSmall),
                          Text(
                            'كرّر نفس الطلب 3 مرات أو احفظه يدوياً',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.verticalSmall),
                    itemCount: templates.length,
                    separatorBuilder: (_, _) => Divider(height: 1),
                    itemBuilder: (ctx, i) => _TemplateCard(
                      template: templates[i],
                      onApply: () {
                        Navigator.pop(context);
                        onApply(templates[i]);
                      },
                      onDelete: () =>
                          ctx.read<OrderTemplatesCubit>().delete(templates[i].id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final OrderTemplate template;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onApply,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(template.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: AppSpacing.horizontalXLarge),
        color: Colors.red,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
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
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onApply,
        leading: Icon(
          template.isManual ? Icons.bookmark : Icons.replay,
          color: template.isManual ? Colors.amber[700] : Colors.grey[600],
        ),
        title: Text(template.itemsSummary,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(template.directionLabel),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (template.isManual)
              const Text('مفضلة',
                  style: TextStyle(fontSize: 11, color: Colors.amber))
            else
              Text('× ${template.usageCount}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700])),
            SizedBox(height: AppSpacing.verticalXSmall),
            const Icon(Icons.chevron_left, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
