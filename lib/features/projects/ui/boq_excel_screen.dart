import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../shared/models/project.dart';
import '../logic/boq_excel_cubit.dart';
import 'boq_import_preview_screen.dart';

/// Opens the add or update flow. Completes with true when lines were written,
/// so the caller knows to reload.
Future<bool> openBoqExcel(
  BuildContext context, {
  required BoqExcelMode mode,
  required Project project,
  required String entityName,
}) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => sl<BoqExcelCubit>(),
        child: BoqExcelScreen(mode: mode, project: project, entityName: entityName),
      ),
    ),
  );
  return changed ?? false;
}

/// Download the file, fill it in, upload it, as on the inventory's Excel
/// screens.
class BoqExcelScreen extends StatelessWidget {
  final BoqExcelMode mode;
  final Project project;
  final String entityName;
  const BoqExcelScreen({
    super.key,
    required this.mode,
    required this.project,
    required this.entityName,
  });

  bool get _isAdd => mode == BoqExcelMode.add;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocConsumer<BoqExcelCubit, BoqExcelState>(
      listenWhen: (prev, curr) =>
          (curr is BoqExcelParsed && curr is! BoqExcelSaving && prev is! BoqExcelParsed) ||
          curr is BoqExcelError,
      listener: (context, state) {
        if (state is BoqExcelParsed) _openPreview(context);
        if (state is BoqExcelError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: scheme.error),
          );
          context.read<BoqExcelCubit>().reset();
        }
      },
      builder: (context, state) {
        final cubit = context.read<BoqExcelCubit>();
        return Scaffold(
          appBar: AppBar(title: Text(_isAdd ? 'إضافة بنود جديدة' : 'تعديل البنود الحالية')),
          body: state is BoqExcelBusy
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(state.message),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 8),
                    _InfoBanner(isAdd: _isAdd),
                    const SizedBox(height: 24),
                    _ActionTile(
                      icon: Icons.download_outlined,
                      title: _isAdd ? 'تنزيل قالب Excel' : 'تصدير البنود الحالية',
                      subtitle: _isAdd
                          ? 'احصل على القالب الجاهز لتعبئة البنود'
                          : 'تنزيل ملف Excel بجميع بنود المشروع الحالية',
                      color: scheme.primaryContainer,
                      iconColor: scheme.primary,
                      onTap: () => _isAdd
                          ? cubit.downloadTemplate(project: project, entityName: entityName)
                          : cubit.exportForUpdate(project: project, entityName: entityName),
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.upload_file_outlined,
                      title: _isAdd ? 'رفع القالب المعبأ' : 'رفع ملف التعديل',
                      subtitle: 'راجع النتائج قبل الحفظ',
                      color: scheme.secondaryContainer,
                      iconColor: scheme.secondary,
                      onTap: () => cubit.pickAndParse(mode, project.id),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openPreview(BuildContext context) async {
    final cubit = context.read<BoqExcelCubit>();
    final applied = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: BoqImportPreviewScreen(mode: mode, projectId: project.id),
        ),
      ),
    );
    if (applied == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isAdd ? 'تمت إضافة $applied بند' : 'تم تحديث $applied بند')),
    );
    Navigator.of(context).pop(true);
  }
}

class _InfoBanner extends StatelessWidget {
  final bool isAdd;
  const _InfoBanner({required this.isAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'كيفية الاستخدام',
                style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isAdd) ...[
            _step('1', 'نزّل قالب Excel'),
            _step('2', 'عبّئ البنود: البند والوحدة إلزاميان، والترقيم تلقائي'),
            _step('3', 'ارفع الملف وراجع النتائج قبل الحفظ'),
          ] else ...[
            _step('1', 'صدِّر ملف Excel بالبنود الحالية'),
            _step('2', 'عدِّل ما تريد — لا تعدِّل عمود الرقم التعريفي'),
            _step('3', 'ارفع الملف وراجع التغييرات قبل الحفظ'),
          ],
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: scheme.tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isAdd
                      ? 'تُضاف البنود بعد البنود الحالية. لتعديل بند موجود استخدم "تعديل البنود الحالية".'
                      : 'هذا الملف لتحديث البنود الموجودة فقط: حذف صف منه لا يحذف البند، ولإضافة بنود جديدة استخدم "إضافة بنود جديدة".',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$num. ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}
