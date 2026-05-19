import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/import_items_cubit.dart';
import '../logic/import_items_state.dart';
import 'import_items_preview_screen.dart';

class ImportItemsScreen extends StatelessWidget {
  const ImportItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ImportItemsCubit, ImportItemsState>(
      listener: (context, state) {
        if (state is ImportItemsParsed) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<ImportItemsCubit>(),
                child: const ImportItemsPreviewScreen(),
              ),
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
      child: Scaffold(
        appBar: AppBar(title: const Text('استيراد عناصر المخزون')),
        body: const _ImportItemsBody(),
      ),
    );
  }
}

class _ImportItemsBody extends StatelessWidget {
  const _ImportItemsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImportItemsCubit, ImportItemsState>(
      builder: (context, state) {
        if (state is ImportItemsParsing) {
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
              title: 'تنزيل قالب Excel',
              subtitle: 'احصل على القالب الجاهز لتعبئة البيانات',
              color: Theme.of(context).colorScheme.primaryContainer,
              iconColor: Theme.of(context).colorScheme.primary,
              onTap: () => context.read<ImportItemsCubit>().downloadTemplate(),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.upload_file_outlined,
              title: 'استيراد من Excel',
              subtitle: 'اختر ملف Excel لاستيراد العناصر',
              color: Theme.of(context).colorScheme.secondaryContainer,
              iconColor: Theme.of(context).colorScheme.secondary,
              onTap: () => context.read<ImportItemsCubit>().pickAndParse(),
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
          _step('1', 'نزّل قالب Excel'),
          _step('2', 'عبّئ بيانات العناصر (الاسم والوحدة والكمية إلزامية)'),
          _step('3', 'استورد الملف وراجع النتائج قبل الحفظ'),
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
