import 'package:flutter/material.dart';
import '../../core/design_system/theme/theme.dart';
import '../models/entity.dart';

class EntityPicker extends StatelessWidget {
  final List<Entity> entities;
  final Entity? selected;
  final ValueChanged<Entity> onChanged;

  /// Category the sheet's filter starts on, so the caller can show the
  /// entities that fit its context first (e.g. توريد for an outbound order).
  /// Null starts on "الكل"; either way the user can switch the chips.
  final EntityCategory? initialCategory;

  const EntityPicker({
    super.key,
    required this.entities,
    required this.selected,
    required this.onChanged,
    this.initialCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showEntitySheet(context, entities),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.horizontalMedium,
            vertical: AppSpacing.verticalLarge,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.name ?? 'اختر...',
                style: TextStyle(
                  color: selected != null ? null : theme.hintColor,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }

  void _showEntitySheet(BuildContext context, List<Entity> entities) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _EntitySheet(
        entities: entities,
        selected: selected,
        initialCategory: initialCategory,
        onSelected: (entity) {
          onChanged(entity);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }
}

class _EntitySheet extends StatefulWidget {
  final List<Entity> entities;
  final Entity? selected;
  final EntityCategory? initialCategory;
  final ValueChanged<Entity> onSelected;

  const _EntitySheet({
    required this.entities,
    required this.selected,
    required this.initialCategory,
    required this.onSelected,
  });

  @override
  State<_EntitySheet> createState() => _EntitySheetState();
}

class _EntitySheetState extends State<_EntitySheet> {
  final TextEditingController _searchController = TextEditingController();
  EntityCategory? _categoryFilter;
  List<Entity> _filtered = [];

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.initialCategory;
    _filtered = _matches();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _onCategoryFilterChanged(EntityCategory? category) {
    setState(() {
      _categoryFilter = category;
    });
    _applyFilters();
  }

  void _applyFilters() {
    setState(() {
      _filtered = _matches();
    });
  }

  List<Entity> _matches() {
    final query = _searchController.text.toLowerCase();
    return widget.entities.where((entity) {
      // Filter by category
      if (_categoryFilter != null && entity.category != _categoryFilter) {
        return false;
      }
      // Filter by search query
      if (query.isNotEmpty && !entity.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: AppSpacing.verticalSmall),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: AppSpacing.allLarge,
              child: Text(
                widget.selected == null ? 'اختر جهة' : 'تغيير الجهة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.horizontalLargePadding,
              child: TextFormField(
                controller: _searchController,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الجهة...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor:
                      theme.inputDecorationTheme.fillColor ??
                      theme.scaffoldBackgroundColor,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.verticalMedium),
            _FilterChips(
              selectedFilter: _categoryFilter,
              onChanged: _onCategoryFilterChanged,
            ),
            SizedBox(height: AppSpacing.verticalSmall),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('لا توجد نتائج'))
                  : Material(
                      color: Colors.transparent,
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final entity = _filtered[index];
                          final isSelected = widget.selected?.id == entity.id;
                          return ListTile(
                            title: Text(entity.name),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: Colors.green)
                                : null,
                            selected: isSelected,
                            selectedTileColor: Colors.green.withValues(
                              alpha: 0.1,
                            ),
                            onTap: () => widget.onSelected(entity),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final EntityCategory? selectedFilter;
  final ValueChanged<EntityCategory?> onChanged;

  const _FilterChips({required this.selectedFilter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Wrap rather than a horizontal scroll strip: a mouse cannot drag one
    // (Flutter omits PointerDeviceKind.mouse from the default drag devices and
    // shows no scrollbar), so on desktop web anything past the right edge is
    // unreachable. These labels are long enough in Arabic to overflow a narrow
    // window.
    return Padding(
      padding: AppSpacing.horizontalLargePadding,
      child: Wrap(
        spacing: AppSpacing.horizontalSmall,
        runSpacing: AppSpacing.verticalSmall,
        children: [
          _FilterChip(
            label: 'الكل',
            isSelected: selectedFilter == null,
            onTap: () => onChanged(null),
          ),
          _FilterChip(
            label: EntityCategory.incoming.label,
            isSelected: selectedFilter == EntityCategory.incoming,
            onTap: () => onChanged(EntityCategory.incoming),
          ),
          _FilterChip(
            label: EntityCategory.outgoing.label,
            isSelected: selectedFilter == EntityCategory.outgoing,
            onTap: () => onChanged(EntityCategory.outgoing),
          ),
        ],
      ),
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
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.horizontalMedium,
        vertical: AppSpacing.verticalSmall,
      ),
    );
  }
}
