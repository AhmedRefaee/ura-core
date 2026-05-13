import 'package:equatable/equatable.dart';

enum ChatMessageType { user, system, action }

class ChatMessageReaction extends Equatable {
  final String emoji;
  final String userId;

  const ChatMessageReaction({required this.emoji, required this.userId});

  factory ChatMessageReaction.fromMap(Map<String, dynamic> map) =>
      ChatMessageReaction(
        emoji: map['emoji'] as String,
        userId: map['user_id'] as String,
      );

  @override
  List<Object?> get props => [emoji, userId];
}

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
  final String? threadTitle;
  // Phase 2 fields
  final ChatMessageType messageType;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSender;
  final String? attachmentUrl;
  final String? attachmentType;
  final String? attachmentName;
  final int? attachmentSizeBytes;
  final List<ChatMessageReaction> reactions;

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
    this.messageType = ChatMessageType.user,
    this.replyToId,
    this.replyToContent,
    this.replyToSender,
    this.attachmentUrl,
    this.attachmentType,
    this.attachmentName,
    this.attachmentSizeBytes,
    this.reactions = const [],
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final threadMap = map['thread'] as Map<String, dynamic>?;
    final rawType = map['message_type'] as String? ?? 'user';
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
      messageType: rawType == 'system'
          ? ChatMessageType.system
          : rawType == 'action'
              ? ChatMessageType.action
              : ChatMessageType.user,
      replyToId: map['reply_to_id'] as String?,
      replyToContent: map['reply_to_content'] as String?,
      replyToSender: map['reply_to_sender'] as String?,
      attachmentUrl: map['attachment_url'] as String?,
      attachmentType: map['attachment_type'] as String?,
      attachmentName: map['attachment_name'] as String?,
      attachmentSizeBytes: map['attachment_size_bytes'] as int?,
      reactions: (map['reactions'] as List<dynamic>?)
              ?.map((r) =>
                  ChatMessageReaction.fromMap(r as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  ChatMessage copyWith({List<ChatMessageReaction>? reactions}) => ChatMessage(
        id: id,
        threadId: threadId,
        senderId: senderId,
        senderName: senderName,
        content: content,
        orderMentionId: orderMentionId,
        orderMentionText: orderMentionText,
        userMentionId: userMentionId,
        userMentionText: userMentionText,
        isUrgent: isUrgent,
        isAcknowledged: isAcknowledged,
        acknowledgedBy: acknowledgedBy,
        acknowledgedAt: acknowledgedAt,
        createdAt: createdAt,
        threadTitle: threadTitle,
        messageType: messageType,
        replyToId: replyToId,
        replyToContent: replyToContent,
        replyToSender: replyToSender,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
        attachmentName: attachmentName,
        attachmentSizeBytes: attachmentSizeBytes,
        reactions: reactions ?? this.reactions,
      );

  @override
  List<Object?> get props => [
        id,
        threadId,
        senderId,
        content,
        isUrgent,
        isAcknowledged,
        createdAt,
        messageType,
        reactions,
      ];
}
