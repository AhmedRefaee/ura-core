class ImportedItemModel {
  final int rowNumber;
  final String? name;
  final String? unit;
  final String? rawQuantity;
  final String? sku;
  final String? category;
  final String? rawAlarmLimit;
  final String? description;
  final String? notes;

  const ImportedItemModel({
    required this.rowNumber,
    this.name,
    this.unit,
    this.rawQuantity,
    this.sku,
    this.category,
    this.rawAlarmLimit,
    this.description,
    this.notes,
  });

  bool get isEmpty => [
        name,
        unit,
        rawQuantity,
        sku,
        category,
        rawAlarmLimit,
        description,
        notes,
      ].every((v) => v == null || v.trim().isEmpty);

  Map<String, dynamic> toInsertMap() => {
        'item_name': name!.trim(),
        'unit': unit!.trim(),
        'quantity': double.parse(rawQuantity!.trim()),
        'sku': _nullIfEmpty(sku),
        'category': _nullIfEmpty(category),
        'min_quantity': rawAlarmLimit == null || rawAlarmLimit!.trim().isEmpty
            ? 0
            : double.parse(rawAlarmLimit!.trim()),
        'description': _nullIfEmpty(description),
        'notes': _nullIfEmpty(notes),
      };

  static String? _nullIfEmpty(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();
}
