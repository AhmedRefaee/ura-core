import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order_template.dart';
import '../logic/template_editor_cubit.dart';
import '../logic/template_management_cubit.dart';
import 'template_editor_screen.dart';

class TemplateManagementScreen extends StatelessWidget {
  const TemplateManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل القوالب')),
      body: Column(
        children: [
          _SearchBar(),
          const Expanded(child: _TemplateGroupList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTemplateEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('قالب جديد'),
      ),
    );
  }
}

/// Pushes the editor for [template] (null = create mode) and refreshes the
/// list when it reports a change.
Future<void> openTemplateEditor(
  BuildContext context,
  OrderTemplate? template,
) async {
  final cubit = context.read<TemplateManagementCubit>();
  final changed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) =>
            sl.get<TemplateEditorCubit>(param1: template)..loadLookups(),
        child: const TemplateEditorScreen(),
      ),
    ),
  );
  if (changed == true && context.mounted) {
    cubit.load();
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          hintText: 'بحث...',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _ctrl.clear();
                    context.read<TemplateManagementCubit>().search('');
                  },
                )
              : null,
        ),
        onChanged: (v) {
          setState(() {});
          context.read<TemplateManagementCubit>().search(v);
        },
      ),
    );
  }
}

// ── List ──────────────────────────────────────────────────────────────────────

class _TemplateGroupList extends StatefulWidget {
  const _TemplateGroupList();

  @override
  State<_TemplateGroupList> createState() => _TemplateGroupListState();
}

class _TemplateGroupListState extends State<_TemplateGroupList> {
  final Map<String, GlobalKey> _groupKeys = {};

  GlobalKey _keyFor(String entityId) =>
      _groupKeys.putIfAbsent(entityId, GlobalKey.new);

  /// Scrolls the focused group into view once, then clears the focus so a
  /// later rebuild (e.g. after a delete) doesn't jump the list again.
  void _consumeFocus(String focusEntityId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _groupKeys[focusEntityId]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 300));
      }
      if (mounted) context.read<TemplateManagementCubit>().clearFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TemplateManagementCubit, TemplateManagementState>(
      builder: (context, state) {
        if (state is TemplateManagementInitial ||
            state is TemplateManagementLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is TemplateManagementError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message, style: const TextStyle(color: Colors.red)),
                SizedBox(height: AppSpacing.verticalMedium),
                FilledButton(
                  onPressed: () =>
                      context.read<TemplateManagementCubit>().load(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        final loaded = state as TemplateManagementLoaded;
        final groups = loaded.groups;
        if (groups.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'لا توجد قوالب',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final focusEntityId = loaded.focusEntityId;
        if (focusEntityId != null) _consumeFocus(focusEntityId);

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.verticalSmall),
          itemCount: groups.length,
          itemBuilder: (context, i) {
            final group = groups[i];
            return _EntityGroupTile(
              key: _keyFor(group.entityId),
              group: group,
              initiallyExpanded: group.entityId == focusEntityId,
            );
          },
        );
      },
    );
  }
}

class _EntityGroupTile extends StatelessWidget {
  final TemplateEntityGroup group;
  final bool initiallyExpanded;

  const _EntityGroupTile({
    super.key,
    required this.group,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: AppSpacing.horizontalMedium,
        vertical: AppSpacing.verticalXSmall,
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        title: Text(
          group.entityName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.horizontalSmall,
            vertical: AppSpacing.verticalXSmall,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${group.count} قوالب',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        children: [
          for (final template in group.templates)
            _TemplateManagementTile(template: template),
        ],
      ),
    );
  }
}

class _TemplateManagementTile extends StatelessWidget {
  final OrderTemplate template;

  const _TemplateManagementTile({required this.template});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(template.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: AppSpacing.horizontalXLarge),
        color: Colors.red,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('حذف القالب'),
            content: const Text('هل تريد حذف هذا القالب؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) =>
          context.read<TemplateManagementCubit>().delete(template.id),
      child: ListTile(
        onTap: () => openTemplateEditor(context, template),
        leading: Icon(
          template.isManual ? Icons.bookmark : Icons.replay,
          color: template.isManual ? Colors.amber[700] : Colors.grey[600],
        ),
        title: Text(
          template.displayTitle,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text('${template.directionLabel} · ${template.itemsSummary}'),
        trailing: const Icon(Icons.chevron_left, size: 16, color: Colors.grey),
      ),
    );
  }
}
