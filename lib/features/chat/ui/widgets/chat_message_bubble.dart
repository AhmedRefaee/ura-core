import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/chat_message.dart';
import '../../../../shared/models/profile.dart';
import '../../../manager/ui/task_detail_screen.dart';
import '../../../profile/ui/profile_screen.dart';

const _kQuickEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡', '🎉', '👏'];

class ChatMessageBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onAcknowledge;
  final void Function(ChatMessage)? onReply;
  final void Function(String messageId, String emoji)? onReactToggle;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onAcknowledge,
    this.onReply,
    this.onReactToggle,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  TapDownDetails? _tapDetails;
  double _dragOffset = 0;
  bool _dragTriggered = false;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  bool get _isMe => widget.message.senderId == _myId;

  // ── System message (centered gray pill) ──────────────────────────────────

  Widget _buildSystemMessage() {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final bgColor = isDark ? theme.colorScheme.surface : Colors.grey.shade200;
        final textColor = isDark ? theme.hintColor : Colors.grey.shade600;
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 12, color: textColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.message.content,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Context menu (long-press) ─────────────────────────────────────────────

  Future<void> _showContextMenu(BuildContext context) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = _tapDetails?.globalPosition ?? const Offset(100, 100);

    // Quick emoji row first
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextSheet(
        message: widget.message,
        isMe: _isMe,
        onReply: widget.onReply,
        onReactToggle: widget.onReactToggle,
        myId: _myId,
        overlaySize: overlay.size,
        tapPos: pos,
      ),
    );
  }

  // ── Swipe gesture ─────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.onReply == null ||
        widget.message.messageType == ChatMessageType.system) {
      return;
    }
    setState(() {
      _dragOffset = (_dragOffset + d.delta.dx).clamp(-60.0, 60.0);
      if (_dragOffset.abs() > 50 && !_dragTriggered) {
        _dragTriggered = true;
        HapticFeedback.mediumImpact();
        widget.onReply?.call(widget.message);
      }
    });
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() {
      _dragOffset = 0;
      _dragTriggered = false;
    });
  }

  // ── Reply-to quoted block ─────────────────────────────────────────────────

  Widget _buildReplyTo() {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surface.withAlpha(128) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
            border: Border(
              left: BorderSide(color: theme.dividerColor, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.message.replyToSender!,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: theme.textTheme.bodyLarge?.color),
              ),
              Text(
                widget.message.replyToContent!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Attachment display ────────────────────────────────────────────────────

  Widget _buildAttachment(BuildContext context) {
    final url = widget.message.attachmentUrl!;
    final type = widget.message.attachmentType ?? 'file';
    final name = widget.message.attachmentName ?? 'ملف';
    final bytes = widget.message.attachmentSizeBytes;
    final sizeLabel = bytes != null ? _formatBytes(bytes) : '';

    if (type == 'image') {
      return GestureDetector(
        onTap: () => _showImageFullscreen(context, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 180,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : SizedBox(
                    height: 180,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  ),
            errorBuilder: (_, _, _) => Container(
              height: 80,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // Generic file card
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surface.withAlpha(180) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type == 'pdf' ? Icons.picture_as_pdf : Icons.attach_file,
                  color: theme.hintColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13, color: theme.textTheme.bodyLarge?.color)),
                      if (sizeLabel.isNotEmpty)
                        Text(sizeLabel,
                            style: TextStyle(
                                fontSize: 11, color: theme.hintColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showImageFullscreen(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reaction chips ────────────────────────────────────────────────────────

  Widget _buildReactions() {
    final msg = widget.message;
    if (msg.reactions.isEmpty) return const SizedBox.shrink();

    // Group by emoji → count + whether I reacted
    final grouped = <String, int>{};
    final myReacted = <String>{};
    for (final r in msg.reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
      if (r.userId == _myId) myReacted.add(r.emoji);
    }

    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 4,
            children: grouped.entries.map((e) {
              final isMine = myReacted.contains(e.key);
              return GestureDetector(
                onTap: () =>
                    widget.onReactToggle?.call(msg.id, e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isMine
                        ? theme.colorScheme.primary.withAlpha(30)
                        : (isDark ? theme.colorScheme.surface.withAlpha(150) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMine
                          ? theme.colorScheme.primary.withAlpha(100)
                          : theme.dividerColor,
                    ),
                  ),
                  child: Text(
                    '${e.key} ${e.value}',
                    style: TextStyle(fontSize: 13, color: theme.textTheme.bodyLarge?.color),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ── Content (text + order/user mention) ──────────────────────────────────

  Widget _buildContent(BuildContext context) {
    final msg = widget.message;

    // Order mention → rich preview card
    if (msg.orderMentionId != null && msg.orderMentionText != null) {
      return _buildOrderCard(
          context, msg.orderMentionId!, msg.orderMentionText!, msg.content);
    }

    // User mention (teal)
    final userText = msg.userMentionText;
    if (userText != null) {
      final mention = '@$userText';
      final idx = msg.content.indexOf(mention);
      if (idx != -1) {
        return _buildWithMention(
          context, msg.content, mention, idx,
          color: Colors.teal.shade700,
          onTap: msg.userMentionId != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        profile: Profile(
                          id: msg.userMentionId!,
                          fullName: userText,
                          isApproved: true,
                        ),
                        isSelf: false,
                      ),
                    ),
                  )
              : null,
        );
      }
    }

    if (msg.content.isEmpty) return const SizedBox.shrink();
    return Text(msg.content,
        style: const TextStyle(fontSize: 14, height: 1.5));
  }

  Widget _buildOrderCard(BuildContext context, String orderId,
      String orderText, String content) {
    final mention = '@$orderText';
    final idx = content.indexOf(mention);
    final before = idx != -1 ? content.substring(0, idx).trim() : '';
    final after =
        idx != -1 ? content.substring(idx + mention.length).trim() : '';

    return Column(
      crossAxisAlignment:
          _isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (before.isNotEmpty) ...[
          Text(before,
              style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 4),
        ],
        Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final primaryColor = theme.colorScheme.primary;
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(orderId: orderId)),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 160),
                decoration: BoxDecoration(
                  color: primaryColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primaryColor.withAlpha(100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: primaryColor.withAlpha(60),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(7)),
                      ),
                      child: Row(children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 13, color: primaryColor),
                        const SizedBox(width: 5),
                        Text('طلب',
                            style: TextStyle(
                                fontSize: 11, color: primaryColor)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Text(orderText,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14, color: theme.textTheme.bodyLarge?.color)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Text('عرض التفاصيل ←',
                          style: TextStyle(
                              fontSize: 11, color: primaryColor)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (after.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(after,
              style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ],
    );
  }

  Widget _buildWithMention(
    BuildContext context,
    String content,
    String mention,
    int idx, {
    required Color color,
    VoidCallback? onTap,
  }) {
    final before = content.substring(0, idx);
    final after = content.substring(idx + mention.length);
    return Wrap(children: [
      if (before.isNotEmpty)
        Text(before, style: const TextStyle(fontSize: 14, height: 1.5)),
      GestureDetector(
        onTap: onTap,
        child: Text(mention,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: color,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            )),
      ),
      if (after.isNotEmpty)
        Text(after, style: const TextStyle(fontSize: 14, height: 1.5)),
    ]);
  }

  // ── Main build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;

    if (msg.messageType == ChatMessageType.system) {
      return _buildSystemMessage();
    }

    final isUrgentPending = msg.isUrgent && !msg.isAcknowledged;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (d) => _tapDetails = d,
      onLongPress: () => _showContextMenu(context),
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: Align(
          alignment:
              _isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isUrgentPending
                  ? Colors.orange.withAlpha(40)
                  : (_isMe
                      ? theme.colorScheme.primary.withAlpha(40)
                      : (isDark ? theme.colorScheme.surface.withAlpha(220) : Colors.white)),
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
                crossAxisAlignment: _isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Sender name (others only)
                  if (!_isMe)
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            profile: Profile(
                              id: msg.senderId,
                              fullName: msg.senderName,
                              isApproved: true,
                            ),
                            isSelf: false,
                          ),
                        ),
                      ),
                      child: Text(
                        msg.senderName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: theme.colorScheme.primary,
                        ),
                      ),
                    ),

                  if (!_isMe) const SizedBox(height: 2),

                  // Reply-to quoted block
                  if (msg.replyToId != null) _buildReplyTo(),

                  // Attachment (image / file)
                  if (msg.attachmentUrl != null) ...[
                    _buildAttachment(context),
                    if (msg.content.isNotEmpty) const SizedBox(height: 6),
                  ],

                  // Text content
                  _buildContent(context),

                  const SizedBox(height: 4),

                  // Timestamp + acknowledge
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(msg.createdAt),
                        style: TextStyle(
                            fontSize: 10, color: theme.hintColor),
                      ),
                      if (isUrgentPending &&
                          widget.onAcknowledge != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onAcknowledge,
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

                  // Reactions row
                  _buildReactions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── Context menu bottom sheet ─────────────────────────────────────────────────

class _ContextSheet extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final void Function(ChatMessage)? onReply;
  final void Function(String, String)? onReactToggle;
  final String? myId;
  final Size overlaySize;
  final Offset tapPos;

  const _ContextSheet({
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.onReactToggle,
    required this.myId,
    required this.overlaySize,
    required this.tapPos,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick emoji row
            if (onReactToggle != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Builder(
                  builder: (context) {
                    final theme = Theme.of(context);
                    final isDark = theme.brightness == Brightness.dark;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _kQuickEmojis.map((emoji) {
                        final myReacted = message.reactions
                            .any((r) => r.emoji == emoji && r.userId == myId);
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            onReactToggle!(message.id, emoji);
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: myReacted
                                  ? theme.colorScheme.primary.withAlpha(40)
                                  : (isDark ? theme.colorScheme.surface.withAlpha(150) : Colors.grey.shade100),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),

            const Divider(height: 1),

            // Copy
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('نسخ'),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(
                    ClipboardData(text: message.content));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ الرسالة'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),

            // Reply
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('رد'),
                onTap: () {
                  Navigator.pop(context);
                  onReply!(message);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
