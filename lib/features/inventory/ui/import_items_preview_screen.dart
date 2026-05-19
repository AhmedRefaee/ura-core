import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/import_items_cubit.dart';
import '../logic/import_items_state.dart';
import 'widgets/import_error_card.dart';
import 'widgets/imported_item_row.dart';

class ImportItemsPreviewScreen extends StatelessWidget {
  const ImportItemsPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImportItemsCubit, ImportItemsState>(
      listener: (context, state) {
        if (state is ImportItemsDone) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم استيراد ${state.insertedCount} عنصر بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is ImportItemsError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is ImportItemsSaving) {
          return Scaffold(
            appBar: AppBar(title: const Text('جارٍ الاستيراد...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! ImportItemsParsed) {
          return Scaffold(
            appBar: AppBar(title: const Text('معاينة الاستيراد')),
            body: const Center(child: Text('لا توجد بيانات للعرض')),
          );
        }

        final hasInvalid = state.invalidItems.isNotEmpty;
        final hasValid = state.validItems.isNotEmpty;

        return Scaffold(
          appBar: AppBar(title: const Text('معاينة الاستيراد')),
          body: Column(
            children: [
              _SummaryHeader(
                total: state.totalRows,
                valid: state.validItems.length,
                invalid: state.invalidItems.length,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    if (hasInvalid) ...[
                      _SectionHeader(
                        title: 'الصفوف بها أخطاء (${state.invalidItems.length})',
                        color: Theme.of(context).colorScheme.error,
                        icon: Icons.error_outline,
                      ),
                      ...state.invalidItems
                          .map((e) => ImportErrorCard(errorItem: e)),
                      const SizedBox(height: 8),
                    ],
                    if (hasValid) ...[
                      _SectionHeader(
                        title: 'الصفوف الصحيحة (${state.validItems.length})',
                        color: Colors.green,
                        icon: Icons.check_circle_outline,
                      ),
                      ...state.validItems
                          .map((e) => ImportedItemRow(item: e)),
                    ],
                    if (!hasValid && !hasInvalid)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('لم يتم العثور على صفوف صالحة'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _BottomActions(
            validCount: state.validItems.length,
            onImport: hasValid
                ? () => context
                    .read<ImportItemsCubit>()
                    .importValidItems(state.validItems)
                : null,
            onCancel: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int total;
  final int valid;
  final int invalid;

  const _SummaryHeader({
    required this.total,
    required this.valid,
    required this.invalid,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatChip(label: 'إجمالي الصفوف', value: total, color: scheme.onSurface),
          _Divider(),
          _StatChip(label: 'صالح للاستيراد', value: valid, color: Colors.green),
          _Divider(),
          _StatChip(label: 'يحتاج تصحيح', value: invalid, color: scheme.error),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: VerticalDivider(
        color: Theme.of(context).dividerColor,
        width: 24,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final int validCount;
  final VoidCallback? onImport;
  final VoidCallback onCancel;

  const _BottomActions({
    required this.validCount,
    required this.onImport,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: const Text('إلغاء'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_rounded),
                label: Text('استيراد $validCount عنصراً صحيحاً'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
