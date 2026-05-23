import 'package:flutter/material.dart';

import '../../data/models/entity_import_error_model.dart';

class EntityImportErrorCard extends StatelessWidget {
  final EntityImportErrorModel errorItem;

  const EntityImportErrorCard({super.key, required this.errorItem});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 18),
                const SizedBox(width: 6),
                Text(
                  'الصف ${errorItem.rowNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                if (errorItem.rawData.name != null &&
                    errorItem.rawData.name!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorItem.rawData.name!,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer
                            .withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ...errorItem.errors.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style:
                            TextStyle(color: colorScheme.onErrorContainer)),
                    Expanded(
                      child: Text(
                        e,
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
