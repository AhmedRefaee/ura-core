import 'package:equatable/equatable.dart';

/// A single line of a project's quotation (خطاب العرض).
///
/// [unitPrice]/[totalPrice] come back null for roles the server-side
/// `get_project_items` RPC doesn't consider commercial -- see
/// `project_item_pricing_visible()` in
/// `supabase/migrations/20260925120100_delivery_receipt_project_items.sql`.
/// A null price here does not mean "no price was set", it means "you're not
/// allowed to see it".
class ProjectItem extends Equatable {
  final String id;
  final String projectId;

  /// Which جدول الكميات table this line sits in. Empty = uncategorized.
  final String category;
  final int sortOrder;
  final String itemName;
  final String? description;
  final double quantity;
  final String unit;
  final double? unitPrice;
  final double? totalPrice;

  /// Packaging the registered [unit] represents, for converting an actual
  /// delivery (see `lib/shared/logic/unit_conversion.dart`) into this
  /// quotation's unit on a سند -- e.g. "1 كرتون = 1.65 كجم × 4" stores
  /// packagingUnitSize 1.65, packagingUnitCount 4, packagingBaseUnit
  /// 'kilogram'. All three null (the common case) means this item has no
  /// such relationship and the سند quantity is entered directly, as always.
  final double? packagingUnitSize;
  final double? packagingUnitCount;
  final String? packagingBaseUnit;
  final DateTime? createdAt;

  const ProjectItem({
    required this.id,
    required this.projectId,
    this.category = '',
    this.sortOrder = 0,
    required this.itemName,
    this.description,
    required this.quantity,
    required this.unit,
    this.unitPrice,
    this.totalPrice,
    this.packagingUnitSize,
    this.packagingUnitCount,
    this.packagingBaseUnit,
    this.createdAt,
  });

  factory ProjectItem.fromMap(Map<String, dynamic> map) {
    return ProjectItem(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      category: map['category'] as String? ?? '',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      itemName: map['item_name'] as String,
      description: map['description'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      unitPrice: (map['unit_price'] as num?)?.toDouble(),
      totalPrice: (map['total_price'] as num?)?.toDouble(),
      packagingUnitSize: (map['packaging_unit_size'] as num?)?.toDouble(),
      packagingUnitCount: (map['packaging_unit_count'] as num?)?.toDouble(),
      packagingBaseUnit: map['packaging_base_unit'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'project_id': projectId,
        'category': category,
        'sort_order': sortOrder,
        'item_name': itemName,
        if (description != null) 'description': description,
        'quantity': quantity,
        'unit': unit,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (totalPrice != null) 'total_price': totalPrice,
        'packaging_unit_size': packagingUnitSize,
        'packaging_unit_count': packagingUnitCount,
        'packaging_base_unit': packagingBaseUnit,
      };

  /// One element of `replace_project_items`' p_items; the server assigns
  /// sort_order from array position. Packaging isn't settable from Excel
  /// import yet, so it's deliberately not sent here.
  Map<String, dynamic> toReplaceJson() => {
        'category': category,
        'item_name': itemName,
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'total_price': totalPrice,
      };

  Map<String, dynamic> toUpdateMap() => {
        'category': category,
        'item_name': itemName,
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'total_price': totalPrice,
        'packaging_unit_size': packagingUnitSize,
        'packaging_unit_count': packagingUnitCount,
        'packaging_base_unit': packagingBaseUnit,
      };

  @override
  List<Object?> get props => [
        id,
        projectId,
        category,
        sortOrder,
        itemName,
        description,
        quantity,
        unit,
        unitPrice,
        totalPrice,
        packagingUnitSize,
        packagingUnitCount,
        packagingBaseUnit,
      ];
}
