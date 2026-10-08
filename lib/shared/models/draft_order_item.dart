import 'package:equatable/equatable.dart';
import 'off_stock_label.dart';

class DraftOrderItem extends Equatable {
  final String? inventoryId;
  final String? inventoryName;
  final double quantity;
  final bool isCustom;
  final String? customDescription;
  final String? sourceInventoryId;

  const DraftOrderItem({
    this.inventoryId,
    this.inventoryName,
    required this.quantity,
    required this.isCustom,
    this.customDescription,
    this.sourceInventoryId,
  });

  String get displayName =>
      isCustom ? (customDescription ?? offStockLabel) : (inventoryName ?? '');

  Map<String, dynamic> toInsertMap() => {
        if (inventoryId != null) 'inventory_id': inventoryId,
        'quantity': quantity,
        'is_custom': isCustom,
        if (customDescription != null) 'custom_description': customDescription,
        if (sourceInventoryId != null) 'source_inventory_id': sourceInventoryId,
      };

  @override
  List<Object?> get props =>
      [inventoryId, quantity, isCustom, customDescription, sourceInventoryId];
}
