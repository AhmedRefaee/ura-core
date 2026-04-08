import 'package:equatable/equatable.dart';

enum UserRole { verifier, rep, storageActor, manager }

class Profile extends Equatable {
  final String id;
  final String fullName;
  final String? phone;
  final UserRole? role;
  final bool isApproved;
  final DateTime? createdAt;

  const Profile({
    required this.id,
    required this.fullName,
    this.phone,
    this.role,
    required this.isApproved,
    this.createdAt,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String?,
      role: _roleFromString(map['role'] as String?),
      isApproved: map['is_approved'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  static UserRole? _roleFromString(String? value) {
    switch (value) {
      case 'verifier':
        return UserRole.verifier;
      case 'rep':
        return UserRole.rep;
      case 'storage_actor':
        return UserRole.storageActor;
      case 'manager':
        return UserRole.manager;
      default:
        return null;
    }
  }

  @override
  List<Object?> get props => [id, fullName, phone, role, isApproved, createdAt];
}
