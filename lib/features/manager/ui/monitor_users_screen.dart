import 'package:flutter/material.dart';
import 'user_type_users_screen.dart';

class MonitorUsersScreen extends StatelessWidget {
  const MonitorUsersScreen({super.key});

  static const _types = [
    (key: 'rep', label: 'المندوبون', icon: Icons.delivery_dining, color: Colors.orange),
    (key: 'storage_actor', label: 'أمناء المخزن', icon: Icons.warehouse, color: Colors.teal),
    (key: 'verifier', label: 'المشرفون', icon: Icons.manage_accounts, color: Colors.indigo),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _types.length,
      itemBuilder: (_, i) {
        final t = _types[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserTypeUsersScreen(
                  roleKey: t.key,
                  roleLabel: t.label,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: t.color.withAlpha(30),
                    child: Icon(t.icon, color: t.color, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      t.label,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
