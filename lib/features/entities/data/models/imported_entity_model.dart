class ImportedEntityModel {
  final int rowNumber;
  final String? id; // present for existing rows; null/empty for new rows
  final String? name;
  final String? rawCategory;
  final String? contactName;
  final String? contactPhone;
  final String? address;

  const ImportedEntityModel({
    required this.rowNumber,
    this.id,
    this.name,
    this.rawCategory,
    this.contactName,
    this.contactPhone,
    this.address,
  });

  bool get isExistingRow => id != null && id!.trim().isNotEmpty;

  bool get isEmpty => [name, rawCategory, contactName, contactPhone, address]
      .every((v) => v == null || v.trim().isEmpty);

  // Returns a map suitable for upsert:
  // - existing rows include 'id' so Supabase updates them
  // - new rows omit 'id' so Supabase inserts them
  Map<String, dynamic> toUpsertMap() => {
        if (isExistingRow) 'id': id!.trim(),
        'name': name!.trim(),
        'category': _categoryDbValue(rawCategory!.trim()),
        if (_nullIfEmpty(contactName) != null) 'contact_name': contactName!.trim(),
        if (_nullIfEmpty(contactPhone) != null) 'contact_phone': contactPhone!.trim(),
        if (_nullIfEmpty(address) != null) 'address': address!.trim(),
      };

  static String _categoryDbValue(String arabic) {
    switch (arabic) {
      case 'وارد':
        return 'incoming';
      case 'صادر':
        return 'outgoing';
      default:
        return 'unassigned';
    }
  }

  static String? _nullIfEmpty(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();
}
