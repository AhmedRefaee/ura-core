import 'package:equatable/equatable.dart';

enum EntityType { customer, supplier }

class Entity extends Equatable {
  final String id;
  final String name;
  final EntityType type;
  final String? contactName;
  final String? contactPhone;
  final String? address;

  const Entity({
    required this.id,
    required this.name,
    required this.type,
    this.contactName,
    this.contactPhone,
    this.address,
  });

  factory Entity.fromMap(Map<String, dynamic> map) {
    return Entity(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] == 'customer' ? EntityType.customer : EntityType.supplier,
      contactName: map['contact_name'] as String?,
      contactPhone: map['contact_phone'] as String?,
      address: map['address'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, type];
}
