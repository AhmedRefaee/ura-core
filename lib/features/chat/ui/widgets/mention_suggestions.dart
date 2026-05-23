import 'package:flutter/material.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/profile.dart';

class MentionSuggestions extends StatelessWidget {
  final String query;
  final List<Profile> members;
  final List<({String id, String displayName})> orders;
  final void Function(String id, String name) onSelectUser;
  final void Function(String id, String name) onSelectOrder;

  const MentionSuggestions({
    super.key,
    required this.query,
    required this.members,
    required this.orders,
    required this.onSelectUser,
    required this.onSelectOrder,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();

    // @all shown when query is empty or matches "الجميع" / "all"
    final showAll =
        q.isEmpty ||
        'الجميع'.contains(q) ||
        'all'.contains(q) ||
        'الكل'.contains(q);

    final filteredMembers = members
        .where((m) => m.fullName.toLowerCase().contains(q))
        .toList();
    final filteredOrders = orders
        .where((o) => o.displayName.toLowerCase().contains(q))
        .toList();

    final allCount = showAll ? 1 : 0;
    final totalCount =
        allCount + filteredMembers.length + filteredOrders.length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: const BorderSide(color: AppColors.borderLight),
          bottom: const BorderSide(color: AppColors.borderLight),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: totalCount == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد نتائج',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: totalCount,
              itemBuilder: (_, i) {
                // @all — always first
                if (showAll && i == 0) {
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primaryLight.withAlpha(45),
                      child: const Icon(
                        Icons.group,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    title: const Text(
                      '@الجميع',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'إشعار جميع أعضاء المجموعة',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () => onSelectUser('', 'الجميع'),
                  );
                }

                final memberIdx = i - allCount;
                if (memberIdx < filteredMembers.length) {
                  final member = filteredMembers[memberIdx];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.infoLight.withAlpha(60),
                      child: const Icon(
                        Icons.person,
                        size: 16,
                        color: AppColors.infoDark,
                      ),
                    ),
                    title: Text(member.fullName),
                    subtitle: Text(
                      _roleLabel(member.role),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => onSelectUser(member.id, member.fullName),
                  );
                }

                final order =
                    filteredOrders[memberIdx - filteredMembers.length];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.accent.withAlpha(40),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: AppColors.accentDark,
                    ),
                  ),
                  title: Text(order.displayName),
                  subtitle: const Text(
                    'طلب نشط',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => onSelectOrder(order.id, order.displayName),
                );
              },
            ),
    );
  }

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.verifier:
        return 'موظف تحقق';
      case UserRole.rep:
        return 'مندوب';
      case UserRole.storageActor:
        return 'مخزن';
      case UserRole.manager:
        return 'مدير';
      default:
        return '';
    }
  }
}
