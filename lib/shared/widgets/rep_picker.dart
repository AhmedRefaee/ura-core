import 'package:flutter/material.dart';
import '../../core/design_system/theme/theme.dart';
import '../models/order.dart';
import '../models/profile.dart';
import '../order_status_theme.dart';

class RepPicker extends StatelessWidget {
  final List<Profile> reps;

  /// Defaults to empty: a template records a *typical* rep for a recurring
  /// order, so the editor has no live dispatch data to show here.
  final Map<String, OrderStatus> repLatestStatuses;
  final Profile? selected;
  final ValueChanged<Profile> onChanged;

  const RepPicker({
    super.key,
    required this.reps,
    this.repLatestStatuses = const {},
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedStatus = selected == null
        ? null
        : repLatestStatuses[selected!.id];
    return InkWell(
      onTap: () => _showRepSheet(context, reps),
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
            if (selectedStatus != null) ...[
              RepStatusAvatar(status: selectedStatus, compact: true),
              SizedBox(width: AppSpacing.horizontalSmall),
            ],
            Expanded(
              child: Text(
                selected?.fullName ?? 'اختر مندوباً...',
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

  void _showRepSheet(BuildContext context, List<Profile> allReps) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RepSheet(
        reps: allReps,
        repLatestStatuses: repLatestStatuses,
        selected: selected,
        onSelected: (rep) {
          onChanged(rep);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }
}

class _RepSheet extends StatefulWidget {
  final List<Profile> reps;
  final Map<String, OrderStatus> repLatestStatuses;
  final Profile? selected;
  final ValueChanged<Profile> onSelected;

  const _RepSheet({
    required this.reps,
    required this.repLatestStatuses,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_RepSheet> createState() => _RepSheetState();
}

class _RepSheetState extends State<_RepSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Profile> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.reps;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.reps
          .where((r) => r.fullName.toLowerCase().contains(query))
          .toList();
    });
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
                widget.selected == null ? 'اختر مندوباً' : 'تغيير المندوب',
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
                  hintText: 'ابحث باسم المندوب...',
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
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('لا توجد نتائج'))
                  : Material(
                      color: Colors.transparent,
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final rep = _filtered[index];
                          final isSelected = widget.selected?.id == rep.id;
                          final latestStatus = widget.repLatestStatuses[rep.id];
                          return ListTile(
                            leading: RepStatusAvatar(status: latestStatus),
                            title: Text(rep.fullName),
                            subtitle: Text(
                              latestStatus == null
                                  ? 'لا يوجد طلب سابق'
                                  : 'آخر طلب: ${repStatusLabel(latestStatus)}',
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: Colors.green)
                                : null,
                            selected: isSelected,
                            selectedTileColor: Colors.green.withValues(
                              alpha: 0.1,
                            ),
                            onTap: () => widget.onSelected(rep),
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

class RepStatusAvatar extends StatelessWidget {
  final OrderStatus? status;
  final bool compact;

  const RepStatusAvatar({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = status?.color ?? Colors.grey;
    final size = compact ? 24.0 : 40.0;
    final iconSize = compact ? 14.0 : 20.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Icon(
        status?.icon ?? Icons.person_outline,
        color: color,
        size: iconSize,
      ),
    );
  }
}

String repStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.assigned:
      return 'معين';
    case OrderStatus.pickedUp:
      return 'تم الاستلام';
    case OrderStatus.onTheMove:
      return 'في الطريق';
    case OrderStatus.delivered:
      return 'تم التسليم';
  }
}
