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
  final String? brand;
  final String? variety;
  final String? rawPackagingSize;
  final String? packagingSizeUnit;
  final String? rawAliases;

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
    this.brand,
    this.variety,
    this.rawPackagingSize,
    this.packagingSizeUnit,
    this.rawAliases,
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
        brand,
        variety,
        rawPackagingSize,
        packagingSizeUnit,
        rawAliases,
      ].every((v) => v == null || v.trim().isEmpty);

  /// Payload for `inventory_bulk_create_items`, not a row of column values --
  /// `notes` is the change-log note the RPC writes to inventory_audit_log, and
  /// `quantity` is a request the server may override (a verifier's is forced to
  /// zero). `row_number` travels along so a server-side failure can name the
  /// spreadsheet row that caused it.
  Map<String, dynamic> toInsertMap() => {
        'row_number': rowNumber,
        'item_name': name!.trim(),
        'unit': unit!.trim(),
        'quantity': double.parse(rawQuantity!.trim()),
        'sku': _nullIfEmpty(sku),
        'category': _nullIfEmpty(category),
        'min_quantity': rawAlarmLimit == null || rawAlarmLimit!.trim().isEmpty
            ? 3
            : double.parse(rawAlarmLimit!.trim()),
        'description': _nullIfEmpty(description),
        'notes': _nullIfEmpty(notes),
        'brand': _nullIfEmpty(brand),
        'variety': _nullIfEmpty(variety),
        'packaging_size': rawPackagingSize == null || rawPackagingSize!.trim().isEmpty
            ? null
            : double.parse(rawPackagingSize!.trim()),
        'packaging_size_unit': _nullIfEmpty(packagingSizeUnit),
        'aliases': _parseAliases(rawAliases),
      };

  static String? _nullIfEmpty(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();

  static List<String>? _parseAliases(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final aliases =
        raw.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    return aliases.isEmpty ? null : aliases;
  }
}
