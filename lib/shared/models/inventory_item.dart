import 'package:equatable/equatable.dart';

class InventoryItem extends Equatable {
  final String id;
  final String itemName;
  final String? sku;
  final int quantity;
  final String unit;

  const InventoryItem({
    required this.id,
    required this.itemName,
    this.sku,
    required this.quantity,
    required this.unit,
  });

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String,
      itemName: map['item_name'] as String,
      sku: map['sku'] as String?,
      quantity: map['quantity'] as int,
      unit: map['unit'] as String? ?? 'قطعة',
    );
  }

  @override
  List<Object?> get props => [id, itemName, sku, quantity, unit];
}
