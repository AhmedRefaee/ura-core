import 'package:equatable/equatable.dart';
import '../utils/quantity_format.dart';
import 'order.dart';

class OrderTemplateItem extends Equatable {
  final String id;
  final String templateId;
  final String? inventoryId;
  final String? inventoryName;
  final double quantity;
  final bool isCustom;
  final String? customDescription;
  final String? sourceInventoryId;

  const OrderTemplateItem({
    required this.id,
    required this.templateId,
    this.inventoryId,
    this.inventoryName,
    required this.quantity,
    required this.isCustom,
    this.customDescription,
    this.sourceInventoryId,
  });

  String get displayName =>
      isCustom ? (customDescription ?? 'صنف مخصص') : (inventoryName ?? '');

  factory OrderTemplateItem.fromMap(Map<String, dynamic> m) => OrderTemplateItem(
        id: m['id'] as String,
        templateId: m['template_id'] as String,
        inventoryId: m['inventory_id'] as String?,
        inventoryName: m['inventory_name'] as String?,
        quantity: (m['quantity'] as num).toDouble(),
        isCustom: m['is_custom'] as bool,
        customDescription: m['custom_description'] as String?,
        sourceInventoryId: m['source_inventory_id'] as String?,
      );

  @override
  List<Object?> get props =>
      [id, templateId, inventoryId, quantity, isCustom, customDescription];
}

class OrderTemplate extends Equatable {
  final String id;
  final String entityId;
  final OrderDirection direction;
  final String? repId;
  final String? notes;
  final bool isManual;
  final int usageCount;
  final List<OrderTemplateItem> items;

  const OrderTemplate({
    required this.id,
    required this.entityId,
    required this.direction,
    this.repId,
    this.notes,
    required this.isManual,
    required this.usageCount,
    required this.items,
  });

  bool get isVisible => isManual || usageCount >= 3;

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

  String get itemsSummary {
    if (items.isEmpty) return 'لا أصناف';
    if (items.length == 1) {
      return '${items.first.displayName} × ${formatQty(items.first.quantity)}';
    }
    return '${items.length} أصناف';
  }

  static OrderDirection _parseDirection(String d) {
    switch (d) {
      case 'inbound_rep':
        return OrderDirection.inboundRep;
      case 'inbound_external':
        return OrderDirection.inboundExternal;
      default:
        return OrderDirection.outbound;
    }
  }

  factory OrderTemplate.fromMap(Map<String, dynamic> m) {
    final rawItems = m['order_template_items'] as List? ?? [];
    return OrderTemplate(
      id: m['id'] as String,
      entityId: m['entity_id'] as String,
      direction: _parseDirection(m['direction'] as String),
      repId: m['rep_id'] as String?,
      notes: m['notes'] as String?,
      isManual: m['is_manual'] as bool,
      usageCount: m['usage_count'] as int,
      items: rawItems
          .map((e) => OrderTemplateItem.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props =>
      [id, entityId, direction, repId, isManual, usageCount, items];
}
