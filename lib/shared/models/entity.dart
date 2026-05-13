import 'package:equatable/equatable.dart';

enum EntityCategory { incoming, outgoing, unassigned }

extension EntityCategoryX on EntityCategory {
  String get label {
    switch (this) {
      case EntityCategory.incoming:
        return 'وارد';
      case EntityCategory.outgoing:
        return 'صادر';
      case EntityCategory.unassigned:
        return 'غير محدد';
    }
  }

  String get dbValue {
    switch (this) {
      case EntityCategory.incoming:
        return 'incoming';
      case EntityCategory.outgoing:
        return 'outgoing';
      case EntityCategory.unassigned:
        return 'unassigned';
    }
  }

  static EntityCategory fromDb(String value) {
    switch (value) {
      case 'outgoing':
        return EntityCategory.outgoing;
      case 'incoming':
        return EntityCategory.incoming;
      default:
        return EntityCategory.unassigned;
    }
  }
}

class Entity extends Equatable {
  final String id;
  final String name;
  final EntityCategory category;
  final String? contactName;
  final String? contactPhone;
  final String? address;

  const Entity({
    required this.id,
    required this.name,
    required this.category,
    this.contactName,
    this.contactPhone,
    this.address,
  });

  factory Entity.fromMap(Map<String, dynamic> map) {
    return Entity(
      id: map['id'] as String,
      name: map['name'] as String,
      category: EntityCategoryX.fromDb(map['category'] as String? ?? 'unassigned'),
      contactName: map['contact_name'] as String?,
      contactPhone: map['contact_phone'] as String?,
      address: map['address'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'category': category.dbValue,
        if (contactName != null) 'contact_name': contactName,
        if (contactPhone != null) 'contact_phone': contactPhone,
        if (address != null) 'address': address,
      };

  Map<String, dynamic> toUpdateMap() => {
        'name': name,
        'category': category.dbValue,
        'contact_name': contactName,
        'contact_phone': contactPhone,
        'address': address,
      };

  @override
  List<Object?> get props => [id, name, category];
}
