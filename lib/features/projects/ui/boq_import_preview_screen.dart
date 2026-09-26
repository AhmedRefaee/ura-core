import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/boq_excel_cubit.dart';
import 'boq_table.dart';

/// Shows what an imported quotation file will become before anything is
/// written. Import replaces every current line, so the confirm button stays
/// disabled while the file has any row it couldn't read.
class BoqImportPreviewScreen extends StatelessWidget {
  final String projectId;
  final int currentItemCount;
  const BoqImportPreviewScreen({super.key, required this.projectId, required this.currentItemCount});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BoqExcelCubit, BoqExcelState>(
      listener: (context, state) {
        if (state is BoqExcelImported || state is BoqExcelError) Navigator.of(context).pop();
      },
      builder: (context, state) {
        if (state is! BoqExcelParsed) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final result = state.result;
        final saving = state is BoqExcelSaving;
        final theme = Theme.of(context);
        final categories = result.categories;

        return PopScope(
          canPop: !saving,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) context.read<BoqExcelCubit>().reset();
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('مراجعة ملف البنود')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(state.fileName, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  '${result.items.length} بند في ${categories.length} ${categories.length == 1 ? 'جدول' : 'جداول'}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (currentItemCount > 0)
                  _Banner(
                    color: theme.colorScheme.tertiaryContainer,
                    icon: Icons.swap_horiz,
                    text: 'سيتم استبدال $currentItemCount بند حالي بـ ${result.items.length} بند من الملف. '
                        'السندات السابقة لن تتأثر.',
                  ),
                if (result.errors.isNotEmpty) ...[
                  _Banner(
                    color: theme.colorScheme.errorContainer,
                    icon: Icons.error_outline,
                    text: 'يوجد ${result.errors.length} صف لم تتم قراءته. صحح الملف ثم أعد الاستيراد.',
                  ),
                  Card(
                    child: Column(children: [
                      for (final e in result.errors)
                        ListTile(
                          dense: true,
                          leading: Text('صف ${e.rowNumber}', style: TextStyle(color: theme.colorScheme.error)),
                          title: Text(e.preview.isEmpty ? '(بدون اسم)' : e.preview),
                          subtitle: Text(e.errors.join('، ')),
                        ),
                    ]),
                  ),
                ],
                if (result.items.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(top: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: BoqTable(items: result.items, showPrices: true),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: result.canImport && !saving
                      ? () => context.read<BoqExcelCubit>().confirmReplace(projectId)
                      : null,
                  icon: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(currentItemCount > 0 ? 'استبدال البنود' : 'استيراد البنود'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
