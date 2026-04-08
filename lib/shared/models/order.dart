import 'package:equatable/equatable.dart';
import 'entity.dart';
import 'order_item.dart';
import 'profile.dart';

enum OrderDirection { outbound, inboundRep, inboundExternal }

enum OrderStatus { assigned, pickedUp, onTheMove, delivered }

class Order extends Equatable {
  final String id;
  final OrderDirection direction;
  final String entityId;
  final Entity? entity;
  final String? repId;
  final Profile? rep;
  final Profile? creator;
  final OrderStatus status;
  final String? notes;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? moveStartedAt;
  final DateTime? deliveredAt;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.direction,
    required this.entityId,
    this.entity,
    this.repId,
    this.rep,
    this.creator,
    required this.status,
    this.notes,
    required this.createdBy,
    this.createdAt,
    this.assignedAt,
    this.pickedUpAt,
    this.moveStartedAt,
    this.deliveredAt,
    this.items = const [],
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    OrderDirection direction;
    switch (map['direction'] as String) {
      case 'inbound_rep':
        direction = OrderDirection.inboundRep;
      case 'inbound_external':
        direction = OrderDirection.inboundExternal;
      default:
        direction = OrderDirection.outbound;
    }

    OrderStatus status;
    switch (map['status'] as String) {
      case 'picked_up':
        status = OrderStatus.pickedUp;
      case 'on_the_move':
        status = OrderStatus.onTheMove;
      case 'delivered':
        status = OrderStatus.delivered;
      default:
        status = OrderStatus.assigned;
    }

    final entityMap = map['entity'] as Map<String, dynamic>?;
    final repMap = map['rep'] as Map<String, dynamic>?;
    final creatorMap = map['creator'] as Map<String, dynamic>?;
    final itemsList = map['order_items'] as List<dynamic>?;

    return Order(
      id: map['id'] as String,
      direction: direction,
      entityId: map['entity_id'] as String,
      entity: entityMap != null ? Entity.fromMap(entityMap) : null,
      repId: map['rep_id'] as String?,
      rep: repMap != null ? Profile.fromMap(repMap) : null,
      creator: creatorMap != null ? Profile.fromMap(creatorMap) : null,
      status: status,
      notes: map['notes'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      assignedAt: map['assigned_at'] != null
          ? DateTime.parse(map['assigned_at'] as String)
          : null,
      pickedUpAt: map['picked_up_at'] != null
          ? DateTime.parse(map['picked_up_at'] as String)
          : null,
      moveStartedAt: map['move_started_at'] != null
          ? DateTime.parse(map['move_started_at'] as String)
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at'] as String)
          : null,
      items: itemsList
              ?.map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get statusLabel {
    switch (status) {
      case OrderStatus.assigned:
        return 'معين';
      case OrderStatus.pickedUp:
        return 'تم الاستلام';
      case OrderStatus.onTheMove:
        return 'في الطريق';
      case OrderStatus.delivered:
        return 'تم التسليم';
    }
  }

  String get directionLabel {
    switch (direction) {
      case OrderDirection.outbound:
        return 'صادر';
      case OrderDirection.inboundRep:
        return 'وارد (مندوب)';
      case OrderDirection.inboundExternal:
        return 'وارد (خارجي)';
    }
  }

  @override
  List<Object?> get props => [id, direction, entityId, repId, status, createdAt];
}
