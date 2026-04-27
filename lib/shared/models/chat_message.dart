import 'package:equatable/equatable.dart';

class ChatMessage extends Equatable {
  final String id;
  final String threadId;
  final String senderId;
  final String senderName;
  final String content;
  final String? orderMentionId;
  final String? orderMentionText;
  final String? userMentionId;
  final String? userMentionText;
  final bool isUrgent;
  final bool isAcknowledged;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  final String? threadTitle; // populated in communication-history queries

  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.orderMentionId,
    this.orderMentionText,
    this.userMentionId,
    this.userMentionText,
    this.isUrgent = false,
    this.isAcknowledged = false,
    this.acknowledgedBy,
    this.acknowledgedAt,
    required this.createdAt,
    this.threadTitle,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final threadMap = map['thread'] as Map<String, dynamic>?;
    return ChatMessage(
      id: map['id'] as String,
      threadId: map['thread_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String? ?? '',
      content: map['content'] as String,
      orderMentionId: map['order_mention_id'] as String?,
      orderMentionText: map['order_mention_text'] as String?,
      userMentionId: map['user_mention_id'] as String?,
      userMentionText: map['user_mention_text'] as String?,
      isUrgent: map['is_urgent'] as bool? ?? false,
      isAcknowledged: map['is_acknowledged'] as bool? ?? false,
      acknowledgedBy: map['acknowledged_by'] as String?,
      acknowledgedAt: map['acknowledged_at'] != null
          ? DateTime.parse(map['acknowledged_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      threadTitle: threadMap?['title'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        threadId,
        senderId,
        content,
        isUrgent,
        isAcknowledged,
        createdAt,
      ];
}
