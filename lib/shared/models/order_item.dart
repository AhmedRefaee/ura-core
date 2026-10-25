import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'profile.dart';
import 'off_stock_label.dart';

enum ItemCheckStatus { pending, checked, rejected }

class OrderItem extends Equatable {
  final String id;
  final String orderId;
  final String? inventoryId;
  final String? inventoryName;

  /// The catalog row's unit; only selected where it is needed (storage).
  final String? inventoryUnit;

  /// The catalog row's stock count, as the app has it; only selected where
  /// it is needed (storage, to spot a count that is not what is on the shelf).
  final double? inventoryStock;
  final double quantity;
  final double? finalQuantity;
  final bool isCustom;
  final String? customDescription;
  final String? sourceInventoryId;
  final ItemCheckStatus checkStatus;
  final String? checkedBy;
  final DateTime? checkedAt;
  final Profile? checker;
  final bool wasUnavailableAtCreation;
  final DateTime? purchasedAt;
  final String? purchasedBy;

  const OrderItem({
    required this.id,
    required this.orderId,
    this.inventoryId,
    this.inventoryName,
    this.inventoryUnit,
    this.inventoryStock,
    required this.quantity,
    this.finalQuantity,
    required this.isCustom,
    this.customDescription,
    this.sourceInventoryId,
    required this.checkStatus,
    this.checkedBy,
    this.checkedAt,
    this.checker,
    this.wasUnavailableAtCreation = false,
    this.purchasedAt,
    this.purchasedBy,
  });

  /// The quantity that should be used for inventory changes.
  /// Storage actor may override this before confirming.
  double get effectiveQuantity => finalQuantity ?? quantity;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    ItemCheckStatus status;
    switch (map['check_status'] as String?) {
      case 'checked':
        status = ItemCheckStatus.checked;
      case 'rejected':
        status = ItemCheckStatus.rejected;
      default:
        status = ItemCheckStatus.pending;
    }

    final inventoryMap = map['inventory'] as Map<String, dynamic>?;
    final checkerMap = map['checker'] as Map<String, dynamic>?;

    return OrderItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      inventoryId: map['inventory_id'] as String?,
      inventoryName: inventoryMap?['item_name'] as String?,
      inventoryUnit: inventoryMap?['unit'] as String?,
      inventoryStock: (inventoryMap?['quantity'] as num?)?.toDouble(),
      quantity: (map['quantity'] as num).toDouble(),
      finalQuantity: (map['final_quantity'] as num?)?.toDouble(),
      isCustom: map['is_custom'] as bool,
      customDescription: map['custom_description'] as String?,
      sourceInventoryId: map['source_inventory_id'] as String?,
      checkStatus: status,
      checkedBy: map['checked_by'] as String?,
      checkedAt: map['checked_at'] != null
          ? DateTime.parse(map['checked_at'] as String)
          : null,
      checker: checkerMap != null ? Profile.fromMap(checkerMap) : null,
      wasUnavailableAtCreation: map['was_unavailable_at_creation'] as bool? ?? false,
      purchasedAt: map['purchased_at'] != null
          ? DateTime.parse(map['purchased_at'] as String)
          : null,
      purchasedBy: map['purchased_by'] as String?,
    );
  }

  Map<String, dynamic>? get customItemJson {
    final desc = customDescription;
    if (desc == null || !desc.startsWith('{')) return null;
    try {
      return jsonDecode(desc) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// A line the verifier typed rather than picked from the catalog -- linked
  /// by storage since or not. A split-off shortfall points at its source row
  /// instead, and a template's catalog line has no typed text at all.
  bool get isTypedLine => customDescription != null && sourceInventoryId == null;

  /// A typed line storage has linked to a catalog row.
  bool get isLinkedTypedLine => isTypedLine && !isCustom && inventoryId != null;

  /// What the verifier wrote as the name.
  String get typedName {
    final json = customItemJson;
    if (json != null) return (json['name'] as String?) ?? '';
    return customDescription ?? '';
  }

  /// The unit the verifier wrote, if any.
  String? get typedUnit => customItemJson?['unit'] as String?;

  String get displayName {
    if (!isCustom) return inventoryName ?? inventoryId ?? '';
    final json = customItemJson;
    if (json != null) return json['name'] as String? ?? offStockLabel;
    return customDescription ?? offStockLabel;
  }

  @override
  List<Object?> get props => [id, orderId, inventoryId, inventoryStock, quantity, finalQuantity, isCustom, sourceInventoryId, checkStatus, wasUnavailableAtCreation, purchasedAt, purchasedBy];
}
