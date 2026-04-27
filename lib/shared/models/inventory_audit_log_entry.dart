import 'package:equatable/equatable.dart';
import 'profile.dart';

class InventoryAuditLogEntry extends Equatable {
  final String id;
  final String itemId;
  final String action;
  final int? oldQuantity;
  final int? newQuantity;
  final String? performedBy;
  final Profile? performer;
  final String? notes;
  final DateTime? performedAt;

  const InventoryAuditLogEntry({
    required this.id,
    required this.itemId,
    required this.action,
    this.oldQuantity,
    this.newQuantity,
    this.performedBy,
    this.performer,
    this.notes,
    this.performedAt,
  });

  factory InventoryAuditLogEntry.fromMap(Map<String, dynamic> map) {
    final performerMap = map['performer'] as Map<String, dynamic>?;
    return InventoryAuditLogEntry(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      action: map['action'] as String,
      oldQuantity: map['old_quantity'] as int?,
      newQuantity: map['new_quantity'] as int?,
      performedBy: map['performed_by'] as String?,
      performer: performerMap != null ? Profile.fromMap(performerMap) : null,
      notes: map['notes'] as String?,
      performedAt: map['performed_at'] != null
          ? DateTime.parse(map['performed_at'] as String)
          : null,
    );
  }

  String get actionLabel {
    switch (action) {
      case 'created':
        return 'إنشاء';
      case 'quantity_updated':
        return 'تعديل الكمية';
      case 'item_updated':
        return 'تعديل البيانات';
      case 'deleted':
        return 'حذف';
      case 'order_pickup':
        return 'صرف بطلب';
      case 'order_delivery':
        return 'استلام بطلب';
      default:
        return action;
    }
  }

  @override
  List<Object?> get props => [id, itemId, action, oldQuantity, newQuantity, performedAt];
}
