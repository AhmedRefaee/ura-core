import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/boq_excel.dart';
import '../logic/boq_excel_cubit.dart';
import 'boq_table.dart';

/// Shows what an uploaded file will do before anything is written, laid out
/// like the inventory's import preview: counts, the rows that need fixing,
/// then the good rows. Bad rows are skipped, so the good ones can still go in.
/// Pops with the number of lines written.
class BoqImportPreviewScreen extends StatelessWidget {
  final BoqExcelMode mode;
  final String projectId;
  const BoqImportPreviewScreen({super.key, required this.mode, required this.projectId});

  bool get _isAdd => mode == BoqExcelMode.add;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BoqExcelCubit, BoqExcelState>(
      listener: (context, state) {
        if (state is BoqExcelApplied) Navigator.of(context).pop(state.count);
        if (state is BoqExcelError) Navigator.of(context).pop();
      },
      builder: (context, state) {
        if (state is! BoqExcelParsed) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final result = state.result;
        final saving = state is BoqExcelSaving;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final count = result.items.length;

        return PopScope(
          canPop: !saving,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) context.read<BoqExcelCubit>().reset();
          },
          child: Scaffold(
            appBar: AppBar(title: Text(_isAdd ? 'معاينة الإضافة' : 'مراجعة التعديلات')),
            // Summary on top, the lazy table takes the rest of the height.
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(state.fileName, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat(label: 'إجمالي الصفوف', value: result.totalRows, color: scheme.onSurface),
                        _Stat(label: _isAdd ? 'صالح للإضافة' : 'سيتم تحديثه', value: count, color: Colors.green),
                        if (!_isAdd)
                          _Stat(label: 'بدون تغيير', value: result.unchangedCount, color: scheme.onSurfaceVariant),
                        _Stat(label: 'يحتاج تصحيح', value: result.errors.length, color: scheme.error),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (result.errors.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'الصفوف بها أخطاء (${result.errors.length}) — لن يتم حفظها',
                        style: theme.textTheme.titleSmall?.copyWith(color: scheme.error, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (count > 0)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: _RowErrors(result.errors),
                      )
                    else
                      Expanded(child: _RowErrors(result.errors)),
                  ],
                  if (count > 0) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _isAdd ? 'البنود الجديدة ($count)' : 'البنود المعدلة ($count)',
                        style: theme.textTheme.titleSmall?.copyWith(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: BoqTable(
                        items: result.items,
                        showPrices: true,
                        numberOf: (item) => item.sortOrder,
                      ),
                    ),
                  ] else if (result.errors.isEmpty)
                    const Expanded(child: Center(child: Text('لا توجد تغييرات في الملف'))),
                ],
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: result.canApply && !saving
                            ? () => context.read<BoqExcelCubit>().apply(projectId)
                            : null,
                        icon: saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: Text(_isAdd ? 'إضافة $count بند' : 'تحديث $count بند'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}

class _RowErrors extends StatelessWidget {
  final List<BoqRowError> errors;
  const _RowErrors(this.errors);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: errors.length,
        itemBuilder: (_, i) {
          final e = errors[i];
          return ListTile(
            dense: true,
            leading: Text('صف ${e.rowNumber}', style: TextStyle(color: theme.colorScheme.error)),
            title: Text(e.preview.isEmpty ? '(بدون اسم)' : e.preview),
            subtitle: Text(e.errors.join('، ')),
          );
        },
      ),
    );
  }
}
