import 'package:equatable/equatable.dart';
import 'profile.dart';

class OrderEditLogEntry extends Equatable {
  final String id;
  final String orderId;
  final String performedBy;
  final Profile? performer;
  final String reason;
  final List<Map<String, dynamic>> changes;
  final DateTime? serverTimestamp;

  const OrderEditLogEntry({
    required this.id,
    required this.orderId,
    required this.performedBy,
    this.performer,
    required this.reason,
    required this.changes,
    this.serverTimestamp,
  });

  factory OrderEditLogEntry.fromMap(Map<String, dynamic> map) {
    final performerMap = map['performer'] as Map<String, dynamic>?;
    final rawChanges = map['changes'];
    final changes = rawChanges is List
        ? rawChanges.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    return OrderEditLogEntry(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      performedBy: map['performed_by'] as String,
      performer: performerMap != null ? Profile.fromMap(performerMap) : null,
      reason: map['reason'] as String,
      changes: changes,
      serverTimestamp: map['server_timestamp'] != null
          ? DateTime.parse(map['server_timestamp'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, orderId, reason, serverTimestamp];
}
