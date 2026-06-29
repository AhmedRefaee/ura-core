import 'package:equatable/equatable.dart';

enum AvailabilityStatus { available, low, outOfStock }

enum StockCheckResult { sufficient, partial, outOfStock }

class InventoryItem extends Equatable {
  final String id;
  final String itemName;
  final String? sku;
  final double quantity;
  final String unit;
  final String? category;
  final double minQuantity;
  final String? description;
  final String? notes;
  // Number of distinct orders that include this item; null means not yet loaded.
  final int? usageCount;

  const InventoryItem({
    required this.id,
    required this.itemName,
    this.sku,
    required this.quantity,
    required this.unit,
    this.category,
    this.minQuantity = 0,
    this.description,
    this.notes,
    this.usageCount,
  });

  AvailabilityStatus get availabilityStatus {
    if (quantity == 0) return AvailabilityStatus.outOfStock;
    if (quantity <= minQuantity) return AvailabilityStatus.low;
    return AvailabilityStatus.available;
  }

  StockCheckResult checkStock(double requestedQuantity) {
    if (quantity == 0) return StockCheckResult.outOfStock;
    if (quantity < requestedQuantity) return StockCheckResult.partial;
    return StockCheckResult.sufficient;
  }

  InventoryItem copyWithUsageCount(int count) => InventoryItem(
        id: id,
        itemName: itemName,
        sku: sku,
        quantity: quantity,
        unit: unit,
        category: category,
        minQuantity: minQuantity,
        description: description,
        notes: notes,
        usageCount: count,
      );

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String,
      itemName: map['item_name'] as String,
      sku: map['sku'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String? ?? 'قطعة',
      category: map['category'] as String?,
      minQuantity: (map['min_quantity'] as num?)?.toDouble() ?? 0,
      description: map['description'] as String?,
      notes: map['notes'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, itemName, sku, quantity, unit, category, minQuantity, description, notes, usageCount];
}
