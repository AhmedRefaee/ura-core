import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/chat_message.dart';
import '../../../manager/ui/task_detail_screen.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onAcknowledge;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onAcknowledge,
  });

  bool get _isMe =>
      message.senderId == Supabase.instance.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    final isUrgentPending = message.isUrgent && !message.isAcknowledged;

    return Align(
      alignment: _isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUrgentPending
              ? Colors.orange.shade50
              : (_isMe ? Colors.blue.shade50 : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: isUrgentPending
                ? const BorderSide(color: Colors.orange, width: 3)
                : BorderSide.none,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment:
                _isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Sender name (for others' messages)
              if (!_isMe)
                Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),

              const SizedBox(height: 2),

              // Message content with @mention link
              _buildContent(context),

              const SizedBox(height: 4),

              // Timestamp + acknowledge button row
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  if (isUrgentPending && onAcknowledge != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onAcknowledge,
                      child: Text(
                        'تأكيد الاستلام',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final content = message.content;

    // User mention (teal) — checked first
    final userText = message.userMentionText;
    if (userText != null) {
      final mention = '@$userText';
      final idx = content.indexOf(mention);
      if (idx != -1) {
        return _buildWithMention(
          context, content, mention, idx,
          color: Colors.teal.shade700,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userText), duration: const Duration(seconds: 2)),
          ),
        );
      }
    }

    // Order mention (blue) — navigates to task detail
    final orderText = message.orderMentionText;
    final orderId = message.orderMentionId;
    if (orderText != null && orderId != null) {
      final mention = '@$orderText';
      final idx = content.indexOf(mention);
      if (idx != -1) {
        return _buildWithMention(
          context, content, mention, idx,
          color: Colors.blue.shade700,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TaskDetailScreen(orderId: orderId)),
          ),
        );
      }
    }

    return Text(content, style: const TextStyle(fontSize: 14));
  }

  Widget _buildWithMention(
    BuildContext context,
    String content,
    String mention,
    int idx, {
    required Color color,
    required VoidCallback onTap,
  }) {
    final before = content.substring(0, idx);
    final after = content.substring(idx + mention.length);
    return Wrap(
      children: [
        if (before.isNotEmpty)
          Text(before, style: const TextStyle(fontSize: 14)),
        GestureDetector(
          onTap: onTap,
          child: Text(
            mention,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        if (after.isNotEmpty)
          Text(after, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
