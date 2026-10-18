import 'package:equatable/equatable.dart';

/// What an outside entity sees through a share link. Deliberately has no
/// quantity or price fields: get_shared_project never sends them, and this
/// model has nowhere to put them even if it did.
class SharedProject extends Equatable {
  final String projectName;
  final String? entityName;
  final String? letterheadPath;
  final List<SharedItem> items;

  const SharedProject({
    required this.projectName,
    this.entityName,
    this.letterheadPath,
    this.items = const [],
  });

  factory SharedProject.fromMap(Map<String, dynamic> map) => SharedProject(
        projectName: map['project_name'] as String? ?? '',
        entityName: map['entity_name'] as String?,
        letterheadPath: map['letterhead_path'] as String?,
        items: [
          for (final e in (map['items'] as List? ?? const []))
            SharedItem.fromMap(e as Map<String, dynamic>),
        ],
      );

  /// Items grouped by category, categories in first-appearance order (the
  /// server already sorts by sort_order). Blank category -> key ''.
  Map<String, List<SharedItem>> get byCategory {
    final groups = <String, List<SharedItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    return groups;
  }

  @override
  List<Object?> get props => [projectName, entityName, letterheadPath, items];
}

class SharedItem extends Equatable {
  final String category;
  final String itemName;
  final String? description;
  final String unit;

  const SharedItem({
    this.category = '',
    required this.itemName,
    this.description,
    required this.unit,
  });

  factory SharedItem.fromMap(Map<String, dynamic> map) => SharedItem(
        category: (map['category'] as String? ?? '').trim(),
        itemName: map['item_name'] as String? ?? '',
        description: switch ((map['description'] as String?)?.trim()) {
          final d? when d.isNotEmpty => d,
          _ => null,
        },
        unit: map['unit'] as String? ?? '',
      );

  @override
  List<Object?> get props => [category, itemName, description, unit];
}

/// A link as its creator sees it in the management sheet.
class ProjectShareLink extends Equatable {
  final String id;
  final String token;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  const ProjectShareLink({
    required this.id,
    required this.token,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
  });

  factory ProjectShareLink.fromMap(Map<String, dynamic> map) => ProjectShareLink(
        id: map['id'] as String,
        token: map['token'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        expiresAt: switch (map['expires_at']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        revokedAt: switch (map['revoked_at']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
      );

  bool isActive([DateTime? now]) =>
      revokedAt == null && (expiresAt == null || expiresAt!.isAfter(now ?? DateTime.now()));

  @override
  List<Object?> get props => [id, token, createdAt, expiresAt, revokedAt];
}
