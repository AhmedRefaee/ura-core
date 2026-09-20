import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'order.dart';
import 'profile.dart';

class AuditLogEntry extends Equatable {
  final String id;
  final String orderId;
  final String action;
  final OrderStatus? oldStatus;
  final OrderStatus? newStatus;
  final String? performedBy;
  final Profile? performer;
  final String? details;
  final String? notes;
  final DateTime? serverTimestamp;
  final double? locationLat;
  final double? locationLng;

  const AuditLogEntry({
    required this.id,
    required this.orderId,
    required this.action,
    this.oldStatus,
    this.newStatus,
    this.performedBy,
    this.performer,
    this.details,
    this.notes,
    this.serverTimestamp,
    this.locationLat,
    this.locationLng,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    final performerMap = map['performer'] as Map<String, dynamic>?;
    return AuditLogEntry(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      action: map['action'] as String,
      oldStatus: _statusFromString(map['old_status'] as String?),
      newStatus: _statusFromString(map['new_status'] as String?),
      performedBy: map['performed_by'] as String?,
      performer: performerMap != null ? Profile.fromMap(performerMap) : null,
      details: map['details'] as String?,
      notes: map['notes'] as String?,
      serverTimestamp: map['server_timestamp'] != null
          ? DateTime.parse(map['server_timestamp'] as String)
          : null,
      locationLat: (map['location_lat'] as num?)?.toDouble(),
      locationLng: (map['location_lng'] as num?)?.toDouble(),
    );
  }

  static OrderStatus? _statusFromString(String? value) {
    switch (value) {
      case 'assigned':
        return OrderStatus.assigned;
      case 'picked_up':
        return OrderStatus.pickedUp;
      case 'on_the_move':
        return OrderStatus.onTheMove;
      case 'delivered':
        return OrderStatus.delivered;
      default:
        return null;
    }
  }

  /// Correlate a per-item toggle-purchase action: extract the item ID from details JSON.
  String? get offStockItemId {
    if (action != 'toggle_off_stock_item_purchased' || details == null) {
      return null;
    }
    try {
      return (jsonDecode(details!) as Map<String, dynamic>)['item_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [id, orderId, action, newStatus, notes, serverTimestamp, locationLat, locationLng];
}

extension AuditLogLookup on List<AuditLogEntry> {
  /// Find the toggle-purchase entry for a given off-stock order item.
  AuditLogEntry? forOffStockItem(String itemId) {
    for (final e in this) {
      if (e.offStockItemId == itemId) return e;
    }
    return null;
  }
}
