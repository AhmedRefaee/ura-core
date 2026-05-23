import 'package:flutter/material.dart';

import '../../data/models/imported_entity_model.dart';

class ImportedEntityRow extends StatelessWidget {
  final ImportedEntityModel item;

  const ImportedEntityRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryColor = _categoryColor(item.rawCategory);
    final badgeColor = item.isExistingRow ? Colors.blue : Colors.green;
    final badgeLabel = item.isExistingRow ? 'تحديث' : 'جديد';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // update/new badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // name + optional contact
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name ?? '',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (item.contactName != null &&
                      item.contactName!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.contactName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // category chip
            if (item.rawCategory != null && item.rawCategory!.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: categoryColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  item.rawCategory!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: categoryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _categoryColor(String? arabic) {
    switch (arabic) {
      case 'وارد':
        return Colors.blue;
      case 'صادر':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
