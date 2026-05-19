import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/models/bulk_edit_item_model.dart';
import '../data/models/bulk_edit_error_model.dart';
import '../logic/bulk_edit_excel_cubit.dart';
import '../logic/bulk_edit_excel_state.dart';
import 'widgets/bulk_edit_error_card.dart';
import 'widgets/bulk_edit_item_row.dart';

class BulkEditExcelPreviewScreen extends StatelessWidget {
  final List<BulkEditItemModel> validItems;
  final List<BulkEditErrorModel> invalidItems;
  final int totalRows;

  const BulkEditExcelPreviewScreen({
    super.key,
    required this.validItems,
    required this.invalidItems,
    required this.totalRows,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<BulkEditExcelCubit, BulkEditExcelState>(
      listener: (context, state) {
        if (state is BulkEditExcelDone) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تحديث ${state.updatedCount} عنصر بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is BulkEditExcelError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('مراجعة التعديلات')),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _SummaryHeader(
                totalRows: totalRows,
                validCount: validItems.length,
                invalidCount: invalidItems.length,
              ),
            ),
            if (invalidItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'الصفوف بها أخطاء (${invalidItems.length})',
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => BulkEditErrorCard(error: invalidItems[i]),
                    childCount: invalidItems.length,
                  ),
                ),
              ),
            ],
            if (validItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'الصفوف الصحيحة (${validItems.length})',
                  color: Colors.green,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => BulkEditItemRow(item: validItems[i]),
                    childCount: validItems.length,
                  ),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _BottomBar(validItems: validItems),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int totalRows;
  final int validCount;
  final int invalidCount;

  const _SummaryHeader({
    required this.totalRows,
    required this.validCount,
    required this.invalidCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'إجمالي الصفوف', value: '$totalRows',
              color: scheme.onSurface),
          _Stat(label: 'صحيح', value: '$validCount', color: Colors.green),
          _Stat(label: 'يحتاج تصحيح', value: '$invalidCount',
              color: scheme.error),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<BulkEditItemModel> validItems;

  const _BottomBar({required this.validItems});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<BulkEditExcelCubit, BulkEditExcelState>(
      builder: (context, state) {
        final isSaving = state is BulkEditExcelSaving;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isSaving ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: validItems.isEmpty || isSaving
                        ? null
                        : () => context
                            .read<BulkEditExcelCubit>()
                            .applyUpdates(validItems),
                    style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('تحديث ${validItems.length} عنصراً'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
