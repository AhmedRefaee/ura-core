import 'package:equatable/equatable.dart';
import 'entity.dart';
import 'profile.dart';
import 'project.dart';

class DeliveryReceiptItem extends Equatable {
  final String id;
  final String deliveryReceiptId;
  final String? projectItemId;
  final String itemNameSnapshot;
  final String unitSnapshot;
  final double quantityDelivered;
  final String? notes;

  const DeliveryReceiptItem({
    required this.id,
    required this.deliveryReceiptId,
    this.projectItemId,
    required this.itemNameSnapshot,
    required this.unitSnapshot,
    required this.quantityDelivered,
    this.notes,
  });

  factory DeliveryReceiptItem.fromMap(Map<String, dynamic> map) {
    return DeliveryReceiptItem(
      id: map['id'] as String,
      deliveryReceiptId: map['delivery_receipt_id'] as String,
      projectItemId: map['project_item_id'] as String?,
      itemNameSnapshot: map['item_name_snapshot'] as String,
      unitSnapshot: map['unit_snapshot'] as String,
      quantityDelivered: (map['quantity_delivered'] as num).toDouble(),
      notes: map['notes'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [id, deliveryReceiptId, projectItemId, itemNameSnapshot, unitSnapshot, quantityDelivered, notes];
}

/// سند استلام -- an immutable logistics record a rep files (optionally tied
/// to an order, never required to be). No UPDATE path exists once created,
/// server-side or in this model: see the header comment in
/// `supabase/migrations/20260925120200_delivery_receipt_receipts.sql`.
class DeliveryReceipt extends Equatable {
  final String id;
  final String entityId;
  final Entity? entity;
  final String projectId;
  final Project? project;
  final String? orderId;
  final String repId;
  final Profile? rep;
  final DateTime? deliveredAt;
  final String? pdfUrl;
  final String? letterheadImageUrlSnapshot;
  final String? notes;
  final DateTime? createdAt;
  final List<DeliveryReceiptItem> items;

  const DeliveryReceipt({
    required this.id,
    required this.entityId,
    this.entity,
    required this.projectId,
    this.project,
    this.orderId,
    required this.repId,
    this.rep,
    this.deliveredAt,
    this.pdfUrl,
    this.letterheadImageUrlSnapshot,
    this.notes,
    this.createdAt,
    this.items = const [],
  });

  factory DeliveryReceipt.fromMap(Map<String, dynamic> map) {
    final entityMap = map['entity'] as Map<String, dynamic>?;
    final projectMap = map['project'] as Map<String, dynamic>?;
    final repMap = map['rep'] as Map<String, dynamic>?;
    final itemsList = map['delivery_receipt_items'] as List<dynamic>?;

    return DeliveryReceipt(
      id: map['id'] as String,
      entityId: map['entity_id'] as String,
      entity: entityMap != null ? Entity.fromMap(entityMap) : null,
      projectId: map['project_id'] as String,
      project: projectMap != null ? Project.fromMap(projectMap) : null,
      orderId: map['order_id'] as String?,
      repId: map['rep_id'] as String,
      rep: repMap != null ? Profile.fromMap(repMap) : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at'] as String)
          : null,
      pdfUrl: map['pdf_url'] as String?,
      letterheadImageUrlSnapshot: map['letterhead_image_url_snapshot'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      items: itemsList
              ?.map((i) => DeliveryReceiptItem.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  @override
  List<Object?> get props =>
      [id, entityId, projectId, orderId, repId, deliveredAt, pdfUrl, notes];
}
