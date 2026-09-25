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
  final String itemName;
  final String? description;
  final double quantity;
  final String unit;
  final double? unitPrice;
  final double? totalPrice;
  final DateTime? createdAt;

  const ProjectItem({
    required this.id,
    required this.projectId,
    required this.itemName,
    this.description,
    required this.quantity,
    required this.unit,
    this.unitPrice,
    this.totalPrice,
    this.createdAt,
  });

  factory ProjectItem.fromMap(Map<String, dynamic> map) {
    return ProjectItem(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      itemName: map['item_name'] as String,
      description: map['description'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      unitPrice: (map['unit_price'] as num?)?.toDouble(),
      totalPrice: (map['total_price'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'project_id': projectId,
        'item_name': itemName,
        if (description != null) 'description': description,
        'quantity': quantity,
        'unit': unit,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (totalPrice != null) 'total_price': totalPrice,
      };

  Map<String, dynamic> toUpdateMap() => {
        'item_name': itemName,
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'total_price': totalPrice,
      };

  @override
  List<Object?> get props =>
      [id, projectId, itemName, description, quantity, unit, unitPrice, totalPrice];
}
