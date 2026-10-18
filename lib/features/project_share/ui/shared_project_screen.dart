import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/storage/signed_storage_url.dart';
import '../logic/shared_project_cubit.dart';
import '../models/shared_project.dart';

/// The public page a share link opens: the project's بنود, read-only, for
/// the outside entity. Reachable signed out -- the router never redirects
/// away from /share/. Shows name, description and unit only; quantities and
/// prices never reach this page (see get_shared_project).
class SharedProjectScreen extends StatelessWidget {
  const SharedProjectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<SharedProjectCubit, SharedProjectState>(
          builder: (context, state) => switch (state) {
            SharedProjectLoading() => const Center(child: CircularProgressIndicator()),
            SharedProjectInvalid() => const _Message(
                icon: Icons.link_off,
                text: 'هذا الرابط غير صالح أو انتهت صلاحيته',
              ),
            SharedProjectError() => _Message(
                icon: Icons.cloud_off,
                text: 'تعذر تحميل البنود، حاول مرة أخرى',
                onRetry: context.read<SharedProjectCubit>().load,
              ),
            SharedProjectLoaded(:final project) => _ProjectView(project: project),
          },
        ),
      ),
    );
  }
}

class _ProjectView extends StatelessWidget {
  final SharedProject project;
  const _ProjectView({required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = project.byCategory;
    var number = 0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (project.letterheadPath != null) ...[
              _Letterhead(path: project.letterheadPath!),
              const SizedBox(height: 16),
            ],
            Text(project.projectName, style: theme.textTheme.headlineSmall),
            if (project.entityName case final entity? when entity.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(entity, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 4),
            Text('بنود العقد (${project.items.length})', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            if (project.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('لا توجد بنود في هذا المشروع بعد')),
              ),
            for (final MapEntry(key: category, value: items) in groups.entries) ...[
              if (category.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(category, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                ),
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, item) in items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _ItemRow(number: ++number, item: item),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'عرض للاطلاع فقط',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final int number;
  final SharedItem item;
  const _ItemRow({required this.number, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text('$number', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.itemName, style: theme.textTheme.titleSmall),
                if (item.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(item.description!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Chip(
            label: Text(item.unit),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _Letterhead extends StatelessWidget {
  final String path;
  const _Letterhead({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: SignedStorageUrl.resolve('project-letterheads', path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}
