import 'package:equatable/equatable.dart';

class ChatThread extends Equatable {
  final String id;
  final String title;
  final String createdBy;
  final DateTime createdAt;
  final bool isDirect;
  final int unreadCount;
  final String? lastMessageContent;
  final String? lastMessageSenderName;
  final DateTime? lastMessageAt;
  final bool systemMessagesEnabled;

  const ChatThread({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    this.isDirect = false,
    this.unreadCount = 0,
    this.lastMessageContent,
    this.lastMessageSenderName,
    this.lastMessageAt,
    this.systemMessagesEnabled = true,
  });

  factory ChatThread.fromMap(Map<String, dynamic> map) {
    return ChatThread(
      id: map['id'] as String,
      title: map['title'] as String,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isDirect: map['is_direct'] as bool? ?? false,
      lastMessageContent: map['last_message_content'] as String?,
      lastMessageSenderName: map['last_message_sender_name'] as String?,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.parse(map['last_message_at'] as String)
          : null,
      systemMessagesEnabled: map['system_messages_enabled'] as bool? ?? true,
    );
  }

  ChatThread copyWith({
    int? unreadCount,
    String? lastMessageContent,
    String? lastMessageSenderName,
    DateTime? lastMessageAt,
    bool? systemMessagesEnabled,
  }) =>
      ChatThread(
        id: id,
        title: title,
        createdBy: createdBy,
        createdAt: createdAt,
        isDirect: isDirect,
        unreadCount: unreadCount ?? this.unreadCount,
        lastMessageContent: lastMessageContent ?? this.lastMessageContent,
        lastMessageSenderName:
            lastMessageSenderName ?? this.lastMessageSenderName,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        systemMessagesEnabled: systemMessagesEnabled ?? this.systemMessagesEnabled,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        createdBy,
        createdAt,
        isDirect,
        unreadCount,
        lastMessageAt,
      ];
}
