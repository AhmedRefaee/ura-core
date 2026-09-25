import 'package:equatable/equatable.dart';

class Project extends Equatable {
  final String id;
  final String entityId;
  final String name;
  final String? letterheadImageUrl;
  final String? createdBy;
  final DateTime? createdAt;

  const Project({
    required this.id,
    required this.entityId,
    required this.name,
    this.letterheadImageUrl,
    this.createdBy,
    this.createdAt,
  });

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as String,
      entityId: map['entity_id'] as String,
      name: map['name'] as String,
      letterheadImageUrl: map['letterhead_image_url'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'entity_id': entityId,
        'name': name,
        if (letterheadImageUrl != null) 'letterhead_image_url': letterheadImageUrl,
      };

  Map<String, dynamic> toUpdateMap() => {
        'name': name,
        'letterhead_image_url': letterheadImageUrl,
      };

  @override
  List<Object?> get props => [id, entityId, name, letterheadImageUrl];
}
