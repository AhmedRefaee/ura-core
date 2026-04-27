import 'package:equatable/equatable.dart';

class ChatThread extends Equatable {
  final String id;
  final String title;
  final String createdBy;
  final DateTime createdAt;
  final bool isDirect;

  const ChatThread({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    this.isDirect = false,
  });

  factory ChatThread.fromMap(Map<String, dynamic> map) {
    return ChatThread(
      id: map['id'] as String,
      title: map['title'] as String,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isDirect: map['is_direct'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, title, createdBy, createdAt, isDirect];
}
