import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'profile.dart';

enum ItemCheckStatus { pending, checked, rejected }

class OrderItem extends Equatable {
  final String id;
  final String orderId;
  final String? inventoryId;
  final String? inventoryName;
  final int quantity;
  final int? finalQuantity;
  final bool isCustom;
  final String? customDescription;
  final String? sourceInventoryId;
  final ItemCheckStatus checkStatus;
  final String? checkedBy;
  final DateTime? checkedAt;
  final Profile? checker;

  const OrderItem({
    required this.id,
    required this.orderId,
    this.inventoryId,
    this.inventoryName,
    required this.quantity,
    this.finalQuantity,
    required this.isCustom,
    this.customDescription,
    this.sourceInventoryId,
    required this.checkStatus,
    this.checkedBy,
    this.checkedAt,
    this.checker,
  });

  /// The quantity that should be used for inventory changes.
  /// Storage actor may override this before confirming.
  int get effectiveQuantity => finalQuantity ?? quantity;

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
      quantity: map['quantity'] as int,
      finalQuantity: map['final_quantity'] as int?,
      isCustom: map['is_custom'] as bool,
      customDescription: map['custom_description'] as String?,
      sourceInventoryId: map['source_inventory_id'] as String?,
      checkStatus: status,
      checkedBy: map['checked_by'] as String?,
      checkedAt: map['checked_at'] != null
          ? DateTime.parse(map['checked_at'] as String)
          : null,
      checker: checkerMap != null ? Profile.fromMap(checkerMap) : null,
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

  String get displayName {
    if (!isCustom) return inventoryName ?? inventoryId ?? '';
    final json = customItemJson;
    if (json != null) return json['name'] as String? ?? 'صنف مخصص';
    return customDescription ?? 'صنف مخصص';
  }

  @override
  List<Object?> get props => [id, orderId, inventoryId, quantity, finalQuantity, isCustom, sourceInventoryId, checkStatus];
}
