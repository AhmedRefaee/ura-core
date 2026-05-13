import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/entity.dart';
import '../logic/entities_cubit.dart';
import 'widgets/entity_form_sheet.dart';

class EntitiesScreen extends StatelessWidget {
  const EntitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الجهات'),
      ),
      body: Column(
        children: [
          _SearchBar(),
          const _FilterBar(),
          const Expanded(child: _EntityList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showEntityFormSheet(context, context.read<EntitiesCubit>()),
        icon: const Icon(Icons.add),
        label: const Text('جهة جديدة'),
      ),
    );
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
                    context.read<EntitiesCubit>().search('');
                  },
                )
              : null,
        ),
        onChanged: (v) {
          setState(() {});
          context.read<EntitiesCubit>().search(v);
        },
      ),
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EntitiesCubit, EntitiesState>(
      builder: (context, state) {
        if (state is! EntitiesLoaded) return const SizedBox.shrink();
        
        final selectedFilter = state.categoryFilter;
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'الكل',
                  isSelected: selectedFilter == null,
                  onTap: () => context.read<EntitiesCubit>().filterByCategory(null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'وارد',
                  isSelected: selectedFilter == EntityCategory.incoming,
                  onTap: () => context.read<EntitiesCubit>().filterByCategory(EntityCategory.incoming),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'صادر',
                  isSelected: selectedFilter == EntityCategory.outgoing,
                  onTap: () => context.read<EntitiesCubit>().filterByCategory(EntityCategory.outgoing),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: theme.colorScheme.surface,
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

// ── Entity list ───────────────────────────────────────────────────────────────

class _EntityList extends StatelessWidget {
  const _EntityList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EntitiesCubit, EntitiesState>(
      builder: (context, state) {
        if (state is EntitiesLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is EntitiesError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.read<EntitiesCubit>().load(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is EntitiesLoaded) {
          final entities = state.filtered;
          if (entities.isEmpty) {
            return const Center(child: Text('لا توجد جهات'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: entities.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) =>
                _EntityTile(entity: entities[i]),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ── Entity tile ───────────────────────────────────────────────────────────────

class _EntityTile extends StatelessWidget {
  final Entity entity;
  const _EntityTile({required this.entity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = _categoryStyle(entity.category);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(entity.name, style: theme.textTheme.bodyLarge),
        subtitle: Text(
          [
            entity.category.label,
            if (entity.contactName != null && entity.contactName!.isNotEmpty)
              entity.contactName!,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<_Action>(
          onSelected: (action) => _onAction(context, action),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _Action.edit,
              child: Row(
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 8),
                  Text('تعديل'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _Action.delete,
              child: Row(
                children: [
                  Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Text('حذف',
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onAction(BuildContext context, _Action action) {
    switch (action) {
      case _Action.edit:
        showEntityFormSheet(
          context,
          context.read<EntitiesCubit>(),
          entity: entity,
        );
      case _Action.delete:
        _confirmDelete(context);
    }
  }

  void _confirmDelete(BuildContext context) {
    final cubit = context.read<EntitiesCubit>();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الجهة'),
        content: Text('هل تريد حذف "${entity.name}"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop(true);
              try {
                await cubit.delete(entity.id);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('فشل الحذف: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  (Color, IconData) _categoryStyle(EntityCategory cat) {
    switch (cat) {
      case EntityCategory.incoming:
        return (Colors.blue, Icons.arrow_downward);
      case EntityCategory.outgoing:
        return (Colors.green, Icons.arrow_upward);
      case EntityCategory.unassigned:
        return (Colors.grey, Icons.swap_horiz);
    }
  }
}

enum _Action { edit, delete }
