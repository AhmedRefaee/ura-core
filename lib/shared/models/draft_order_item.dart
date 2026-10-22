import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'off_stock_label.dart';

class DraftOrderItem extends Equatable {
  final String? inventoryId;
  final String? inventoryName;
  final double quantity;
  final bool isCustom;
  final String? customDescription;
  final String? sourceInventoryId;

  /// Identifies this line while the verifier edits it, so a row keeps its own
  /// text fields when another row is edited or deleted. Not saved and not part
  /// of equality.
  final int? rowKey;

  const DraftOrderItem({
    this.inventoryId,
    this.inventoryName,
    required this.quantity,
    required this.isCustom,
    this.customDescription,
    this.sourceInventoryId,
    this.rowKey,
  });

  /// A line the verifier typed: just a name, a unit and a quantity. Whether
  /// storage has it is storage's call, not the verifier's.
  factory DraftOrderItem.typed({
    required String name,
    String unit = '',
    required double quantity,
  }) =>
      DraftOrderItem(
        quantity: quantity,
        isCustom: true,
        customDescription: _payload({}, name: name, unit: unit, quantity: quantity),
        rowKey: nextRowKey(),
      );

  static int _rowKeySeq = 0;
  static int nextRowKey() => ++_rowKeySeq;

  /// This item with a [rowKey], assigning a fresh one if it has none.
  DraftOrderItem keyed() => rowKey != null ? this : _copy(rowKey: nextRowKey());

  /// The JSON payload of a custom item ({"name": ..., "unit": ...}), or null
  /// for a catalog row or a plain-text description.
  Map<String, dynamic>? get customJson {
    final desc = customDescription;
    if (!isCustom || desc == null || !desc.startsWith('{')) return null;
    try {
      return jsonDecode(desc) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// What the verifier typed as the name; '' for a catalog row.
  String get typedName {
    if (!isCustom) return '';
    final json = customJson;
    if (json != null) return (json['name'] as String?) ?? '';
    return customDescription ?? '';
  }

  String get typedUnit => (customJson?['unit'] as String?) ?? '';

  /// Ready to be sent: a quantity above zero and, for a typed line, a name.
  bool get isComplete =>
      quantity > 0 && (!isCustom || typedName.trim().isNotEmpty);

  String get displayName {
    if (!isCustom) return inventoryName ?? '';
    if (customDescription == null) return offStockLabel;
    final name = typedName;
    return name.isNotEmpty ? name : customDescription!;
  }

  /// A typed line with its name / unit / quantity changed. Every other field
  /// of its payload (brand, variety, packaging...) is kept.
  DraftOrderItem withTyped({String? name, String? unit, double? quantity}) {
    final q = quantity ?? this.quantity;
    return _copy(
      quantity: q,
      customDescription: _payload(
        customJson ?? {'name': typedName, 'minQty': 0},
        name: name,
        unit: unit,
        quantity: q,
      ),
    );
  }

  DraftOrderItem withQuantity(double quantity) {
    if (isCustom) return withTyped(quantity: quantity);
    return _copy(quantity: quantity);
  }

  static String _payload(
    Map<String, dynamic> base, {
    String? name,
    String? unit,
    required double quantity,
  }) {
    final json = Map<String, dynamic>.from(base);
    if (name != null) json['name'] = name.trim();
    // No unit written stays unwritten; everything that reads the payload
    // already falls back to قطعة.
    if (unit != null && unit.trim().isEmpty) {
      json.remove('unit');
    } else if (unit != null) {
      json['unit'] = unit.trim();
    }
    json['qty'] = quantity;
    json['minQty'] ??= 0;
    return jsonEncode(json);
  }

  DraftOrderItem _copy({double? quantity, String? customDescription, int? rowKey}) =>
      DraftOrderItem(
        inventoryId: inventoryId,
        inventoryName: inventoryName,
        quantity: quantity ?? this.quantity,
        isCustom: isCustom,
        customDescription: customDescription ?? this.customDescription,
        sourceInventoryId: sourceInventoryId,
        rowKey: rowKey ?? this.rowKey,
      );

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
