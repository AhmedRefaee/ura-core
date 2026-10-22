import 'package:equatable/equatable.dart';
import '../../../shared/models/delivery_receipt.dart' show ReceiptStatus;
import '../../../shared/models/entity.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';

/// What an outside entity sees through a share link. Deliberately has no
/// quantity or price fields: get_shared_project never sends them, and this
/// model has nowhere to put them even if it did.
class SharedProject extends Equatable {
  final String projectName;
  final String? entityName;
  final String? letterheadPath;

  /// Whether this link may also file سندات for approval.
  final bool canSubmit;
  final List<SharedItem> items;

  const SharedProject({
    required this.projectName,
    this.entityName,
    this.letterheadPath,
    this.canSubmit = false,
    this.items = const [],
  });

  factory SharedProject.fromMap(Map<String, dynamic> map) => SharedProject(
        projectName: map['project_name'] as String? ?? '',
        entityName: map['entity_name'] as String?,
        letterheadPath: map['letterhead_path'] as String?,
        canSubmit: map['can_submit'] as bool? ?? false,
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

  /// The shapes the سند screen already works with. The ids are placeholders:
  /// a link holder never learns the project's or entity's real ids, only the
  /// items' (needed to name them in a submission). Quantity is always 0 --
  /// the project's quantities are exactly what a link must not reveal.
  Entity get asEntity => Entity(
        id: 'portal-entity',
        name: entityName ?? '',
        category: EntityCategory.unassigned,
      );

  Project get asProject => Project(
        id: 'portal-project',
        entityId: 'portal-entity',
        name: projectName,
        letterheadImageUrl: letterheadPath,
      );

  List<ProjectItem> get asProjectItems => [
        for (final (i, item) in items.indexed)
          ProjectItem(
            id: item.id,
            projectId: 'portal-project',
            category: item.category,
            sortOrder: i,
            itemName: item.itemName,
            description: item.description,
            quantity: 0,
            unit: item.unit,
            packagingUnitSize: item.packagingUnitSize,
            packagingUnitCount: item.packagingUnitCount,
            packagingBaseUnit: item.packagingBaseUnit,
          ),
      ];

  @override
  List<Object?> get props => [projectName, entityName, letterheadPath, canSubmit, items];
}

class SharedItem extends Equatable {
  final String id;
  final String category;
  final String itemName;
  final String? description;
  final String unit;

  /// Packaging the unit represents (drives the quantity calculator); says
  /// nothing about how much the project buys.
  final double? packagingUnitSize;
  final double? packagingUnitCount;
  final String? packagingBaseUnit;

  const SharedItem({
    this.id = '',
    this.category = '',
    required this.itemName,
    this.description,
    required this.unit,
    this.packagingUnitSize,
    this.packagingUnitCount,
    this.packagingBaseUnit,
  });

  factory SharedItem.fromMap(Map<String, dynamic> map) => SharedItem(
        id: map['id'] as String? ?? '',
        category: (map['category'] as String? ?? '').trim(),
        itemName: map['item_name'] as String? ?? '',
        description: switch ((map['description'] as String?)?.trim()) {
          final d? when d.isNotEmpty => d,
          _ => null,
        },
        unit: map['unit'] as String? ?? '',
        packagingUnitSize: (map['packaging_unit_size'] as num?)?.toDouble(),
        packagingUnitCount: (map['packaging_unit_count'] as num?)?.toDouble(),
        packagingBaseUnit: map['packaging_base_unit'] as String?,
      );

  @override
  List<Object?> get props =>
      [id, category, itemName, description, unit, packagingUnitSize, packagingUnitCount, packagingBaseUnit];
}

/// A link as its creator sees it in the management sheet.
class ProjectShareLink extends Equatable {
  final String id;
  final String token;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final bool canSubmit;

  const ProjectShareLink({
    required this.id,
    required this.token,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
    this.canSubmit = false,
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
        canSubmit: map['can_submit'] as bool? ?? false,
      );

  bool isActive([DateTime? now]) =>
      revokedAt == null && (expiresAt == null || expiresAt!.isAfter(now ?? DateTime.now()));

  @override
  List<Object?> get props => [id, token, createdAt, expiresAt, revokedAt, canSubmit];
}

class SharedReceiptLine extends Equatable {
  final String? projectItemId;
  final String itemName;
  final String unit;
  final double quantity;
  final String? notes;

  const SharedReceiptLine({
    this.projectItemId,
    required this.itemName,
    required this.unit,
    required this.quantity,
    this.notes,
  });

  factory SharedReceiptLine.fromMap(Map<String, dynamic> map) => SharedReceiptLine(
        projectItemId: map['project_item_id'] as String?,
        itemName: map['item_name'] as String? ?? '',
        unit: map['unit'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
      );

  @override
  List<Object?> get props => [projectItemId, itemName, unit, quantity, notes];
}

class SharedReceipt extends Equatable {
  final String id;
  final ReceiptStatus status;
  final DateTime createdAt;
  final String? submitterName;
  final String? notes;
  final String dateMode;
  final DateTime? customDate;
  final bool fullDescription;

  /// Set when the submitter split by category; the PDF's heading.
  final String? category;
  final List<SharedReceiptLine> lines;

  const SharedReceipt({
    required this.id,
    required this.status,
    required this.createdAt,
    this.submitterName,
    this.notes,
    this.dateMode = 'today',
    this.customDate,
    this.fullDescription = false,
    this.category,
    this.lines = const [],
  });

  factory SharedReceipt.fromMap(Map<String, dynamic> map) {
    final meta = (map['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SharedReceipt(
      id: map['id'] as String,
      status: switch (map['status']) {
        'approved' => ReceiptStatus.approved,
        'rejected' => ReceiptStatus.rejected,
        _ => ReceiptStatus.pending,
      },
      createdAt: DateTime.parse(map['created_at'] as String),
      submitterName: map['submitter_name'] as String?,
      notes: map['notes'] as String?,
      dateMode: meta['date_mode'] as String? ?? 'today',
      customDate: switch (meta['custom_date']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      fullDescription: meta['full_description'] as bool? ?? false,
      category: meta['category'] as String?,
      lines: [
        for (final e in (map['items'] as List? ?? const []))
          SharedReceiptLine.fromMap(e as Map<String, dynamic>),
      ],
    );
  }

  @override
  List<Object?> get props =>
      [id, status, createdAt, submitterName, notes, dateMode, customDate, fullDescription, category, lines];
}
