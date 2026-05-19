import 'package:flutter/material.dart';

import '../../data/models/bulk_edit_error_model.dart';

class BulkEditErrorCard extends StatelessWidget {
  final BulkEditErrorModel error;

  const BulkEditErrorCard({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الصف ${error.rowNumber}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onErrorContainer,
                ),
          ),
          const SizedBox(height: 4),
          ...error.errors.map(
            (e) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ',
                      style: TextStyle(
                          color: scheme.error, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      e,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
