import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/bulk_edit_excel_cubit.dart';
import '../logic/bulk_edit_excel_state.dart';
import 'bulk_edit_excel_preview_screen.dart';

class BulkEditExcelScreen extends StatelessWidget {
  const BulkEditExcelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<BulkEditExcelCubit, BulkEditExcelState>(
      listener: (context, state) {
        if (state is BulkEditExcelParsed) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<BulkEditExcelCubit>(),
                child: BulkEditExcelPreviewScreen(
                  validItems: state.validItems,
                  invalidItems: state.invalidItems,
                  totalRows: state.totalRows,
                ),
              ),
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
        appBar: AppBar(title: const Text('التعديل الجماعي عبر Excel')),
        body: const _BulkEditBody(),
      ),
    );
  }
}

class _BulkEditBody extends StatelessWidget {
  const _BulkEditBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BulkEditExcelCubit, BulkEditExcelState>(
      builder: (context, state) {
        if (state is BulkEditExcelExporting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جارٍ تصدير البيانات...'),
              ],
            ),
          );
        }

        if (state is BulkEditExcelParsing) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جارٍ تحليل الملف...'),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            _InfoBanner(),
            const SizedBox(height: 24),
            _ActionTile(
              icon: Icons.download_outlined,
              title: 'تصدير البيانات الحالية',
              subtitle: 'تنزيل ملف Excel بجميع عناصر المخزون الحالية',
              color: Theme.of(context).colorScheme.primaryContainer,
              iconColor: Theme.of(context).colorScheme.primary,
              onTap: () =>
                  context.read<BulkEditExcelCubit>().exportCurrentItems(),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.upload_file_outlined,
              title: 'استيراد ملف التعديل',
              subtitle: 'اختر ملف Excel المعدَّل لمراجعة التغييرات وتطبيقها',
              color: Theme.of(context).colorScheme.secondaryContainer,
              iconColor: Theme.of(context).colorScheme.secondary,
              onTap: () =>
                  context.read<BulkEditExcelCubit>().pickAndParseBulkEdit(),
            ),
          ],
        );
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _step('1', 'صدِّر ملف Excel الذي يحتوي على البيانات الحالية'),
          _step('2', 'عدِّل أي حقل تريده — لا تعدِّل عمود الرقم التعريفي'),
          _step('3', 'استورد الملف المعدَّل وراجع التغييرات قبل الحفظ'),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: scheme.tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'ملف التعديل الجماعي مخصص لتحديث العناصر الموجودة فقط. '
                  'لإضافة عناصر جديدة استخدم "استيراد عناصر جديدة".',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
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
