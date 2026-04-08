import 'package:equatable/equatable.dart';
import 'profile.dart';

enum ItemCheckStatus { pending, checked, rejected }

class OrderItem extends Equatable {
  final String id;
  final String orderId;
  final String? inventoryId;
  final String? inventoryName;
  final int quantity;
  final bool isCustom;
  final String? customDescription;
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
    required this.isCustom,
    this.customDescription,
    required this.checkStatus,
    this.checkedBy,
    this.checkedAt,
    this.checker,
  });

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
      isCustom: map['is_custom'] as bool,
      customDescription: map['custom_description'] as String?,
      checkStatus: status,
      checkedBy: map['checked_by'] as String?,
      checkedAt: map['checked_at'] != null
          ? DateTime.parse(map['checked_at'] as String)
          : null,
      checker: checkerMap != null ? Profile.fromMap(checkerMap) : null,
    );
  }

  String get displayName =>
      isCustom ? (customDescription ?? 'صنف مخصص') : (inventoryName ?? inventoryId ?? '');

  @override
  List<Object?> get props => [id, orderId, inventoryId, quantity, isCustom, checkStatus];
}
