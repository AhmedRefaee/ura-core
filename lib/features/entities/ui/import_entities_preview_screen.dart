import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/import_entities_cubit.dart';
import '../logic/import_entities_state.dart';
import 'widgets/entity_import_error_card.dart';
import 'widgets/imported_entity_row.dart';

class ImportEntitiesPreviewScreen extends StatelessWidget {
  const ImportEntitiesPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImportEntitiesCubit, ImportEntitiesState>(
      listener: (context, state) {
        if (state is ImportEntitiesDone) {
          Navigator.of(context).pop(true);
          final parts = <String>[];
          if (state.updatedCount > 0) parts.add('تحديث ${state.updatedCount}');
          if (state.insertedCount > 0) parts.add('إضافة ${state.insertedCount}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم ${parts.join(' و')} جهة بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is ImportEntitiesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is ImportEntitiesSaving) {
          return Scaffold(
            appBar: AppBar(title: const Text('جارٍ تطبيق التغييرات...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! ImportEntitiesParsed) {
          return Scaffold(
            appBar: AppBar(title: const Text('معاينة التغييرات')),
            body: const Center(child: Text('لا توجد بيانات للعرض')),
          );
        }

        final updateRows =
            state.validItems.where((e) => e.isExistingRow).toList();
        final insertRows =
            state.validItems.where((e) => !e.isExistingRow).toList();
        final hasInvalid = state.invalidItems.isNotEmpty;
        final hasValid = state.validItems.isNotEmpty;

        return Scaffold(
          appBar: AppBar(title: const Text('معاينة التغييرات')),
          body: Column(
            children: [
              _SummaryHeader(
                total: state.totalRows,
                updateCount: updateRows.length,
                insertCount: insertRows.length,
                invalidCount: state.invalidItems.length,
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
                          .map((e) => EntityImportErrorCard(errorItem: e)),
                      const SizedBox(height: 8),
                    ],
                    if (updateRows.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'تحديث (${updateRows.length})',
                        color: Colors.blue,
                        icon: Icons.edit_outlined,
                      ),
                      ...updateRows.map((e) => ImportedEntityRow(item: e)),
                    ],
                    if (insertRows.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'إضافة جديدة (${insertRows.length})',
                        color: Colors.green,
                        icon: Icons.add_circle_outline,
                      ),
                      ...insertRows.map((e) => ImportedEntityRow(item: e)),
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
            updateCount: updateRows.length,
            insertCount: insertRows.length,
            onApply: hasValid
                ? () => context
                    .read<ImportEntitiesCubit>()
                    .applyChanges(state.validItems)
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
  final int updateCount;
  final int insertCount;
  final int invalidCount;

  const _SummaryHeader({
    required this.total,
    required this.updateCount,
    required this.insertCount,
    required this.invalidCount,
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
          _StatChip(label: 'الإجمالي', value: total, color: scheme.onSurface),
          _Divider(),
          _StatChip(label: 'تحديث', value: updateCount, color: Colors.blue),
          _Divider(),
          _StatChip(label: 'جديد', value: insertCount, color: Colors.green),
          _Divider(),
          _StatChip(label: 'أخطاء', value: invalidCount, color: scheme.error),
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
  final int updateCount;
  final int insertCount;
  final VoidCallback? onApply;
  final VoidCallback onCancel;

  const _BottomActions({
    required this.updateCount,
    required this.insertCount,
    required this.onApply,
    required this.onCancel,
  });

  String get _label {
    final parts = <String>[];
    if (updateCount > 0) parts.add('تحديث $updateCount');
    if (insertCount > 0) parts.add('إضافة $insertCount');
    return parts.join(' و');
  }

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
                onPressed: onApply,
                icon: const Icon(Icons.check_rounded),
                label: Text(_label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
