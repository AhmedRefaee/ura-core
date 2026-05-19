import 'package:flutter/material.dart';

/// Blocking error view for orders with no items.
/// Replaces the entire detail body — no action buttons, no item list.
/// Backend RPCs also reject 0-item orders, so this is a defense-in-depth layer.
class InvalidOrderView extends StatelessWidget {
  const InvalidOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            const Text(
              'هذا الطلب غير صالح لأنه لا يحتوي على عناصر',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'لا يمكن معالجة هذا الطلب. يرجى التواصل مع المسؤول.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
