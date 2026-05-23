import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/import_entities_cubit.dart';
import '../logic/import_entities_state.dart';
import 'import_entities_preview_screen.dart';

class ImportEntitiesScreen extends StatelessWidget {
  const ImportEntitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ImportEntitiesCubit, ImportEntitiesState>(
      listener: (context, state) {
        if (state is ImportEntitiesParsed) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<ImportEntitiesCubit>(),
                child: const ImportEntitiesPreviewScreen(),
              ),
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
      child: Scaffold(
        appBar: AppBar(title: const Text('إدارة الجهات عبر Excel')),
        body: const _Body(),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImportEntitiesCubit, ImportEntitiesState>(
      builder: (context, state) {
        if (state is ImportEntitiesExporting) {
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

        if (state is ImportEntitiesParsing) {
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
            const _InfoBanner(),
            const SizedBox(height: 24),
            _ActionTile(
              icon: Icons.download_outlined,
              title: 'تصدير الجهات الحالية',
              subtitle: 'تنزيل ملف Excel بجميع الجهات الحالية',
              color: Theme.of(context).colorScheme.primaryContainer,
              iconColor: Theme.of(context).colorScheme.primary,
              onTap: () =>
                  context.read<ImportEntitiesCubit>().exportEntities(),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.upload_file_outlined,
              title: 'استيراد الملف المعدَّل',
              subtitle: 'اختر ملف Excel لمراجعة التغييرات وتطبيقها',
              color: Theme.of(context).colorScheme.secondaryContainer,
              iconColor: Theme.of(context).colorScheme.secondary,
              onTap: () => context.read<ImportEntitiesCubit>().pickAndParse(),
            ),
          ],
        );
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

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
          _step('1', 'صدِّر الجهات الحالية — ستحصل على ملف Excel بكل البيانات'),
          _step('2', 'عدِّل أي صف أو أضف صفوفاً جديدة — لا تعدِّل عمود الرقم التعريفي'),
          _step('3', 'التصنيف يجب أن يكون: وارد أو صادر أو غير محدد'),
          _step('4', 'استورد الملف المعدَّل وراجع التغييرات قبل الحفظ'),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: scheme.tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'الصفوف ذات الرقم التعريفي ستُحدَّث، والصفوف بدون رقم تعريفي ستُضاف كجهات جديدة.',
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
