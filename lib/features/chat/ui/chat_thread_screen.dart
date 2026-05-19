import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../features/auth/logic/auth_cubit.dart';
import '../../../features/auth/logic/auth_state.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/profile.dart';
import '../../profile/ui/profile_screen.dart';
import '../data/chat_repository.dart';
import '../logic/chat_thread_cubit.dart';
import 'thread_members_screen.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/mention_suggestions.dart';

class ChatThreadScreen extends StatelessWidget {
  final String threadId;
  final String threadTitle;
  final String? initialText;
  final bool isUrgentEntry;
  final String? mentionedOrderId;
  final String? mentionedOrderTitle;
  final bool isDirect;
  final String? createdBy;

  const ChatThreadScreen({
    super.key,
    required this.threadId,
    required this.threadTitle,
    this.initialText,
    this.isUrgentEntry = false,
    this.mentionedOrderId,
    this.mentionedOrderTitle,
    this.isDirect = false,
    this.createdBy,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatThreadCubit(
        sl<ChatRepository>(),
        threadId: threadId,
        initialText: initialText,
        isUrgentEntry: isUrgentEntry,
        mentionedOrderId: mentionedOrderId,
        mentionedOrderTitle: mentionedOrderTitle,
      )..subscribe(),
      child: _ChatThreadView(
        threadId: threadId,
        threadTitle: threadTitle,
        isUrgentEntry: isUrgentEntry,
        isDirect: isDirect,
        createdBy: createdBy,
      ),
    );
  }
}

// ── Main view — owns scroll controller and reply notifier only ────────────────

class _ChatThreadView extends StatefulWidget {
  final String threadId;
  final String threadTitle;
  final bool isUrgentEntry;
  final bool isDirect;
  final String? createdBy;

  const _ChatThreadView({
    required this.threadId,
    required this.threadTitle,
    required this.isUrgentEntry,
    required this.isDirect,
    this.createdBy,
  });

  @override
  State<_ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<_ChatThreadView> {
  final _scrollController = ScrollController();
  final _replyNotifier = ValueNotifier<ChatMessage?>(null);
  bool _initialized = false;

  // Loaded once and passed to input bar — no setState here on reload
  List<Profile> _threadMembers = [];
  List<({String id, String displayName})> _activeOrders = [];

  @override
  void initState() {
    super.initState();
    _loadMentionData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _replyNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadMentionData() async {
    final repo = sl<ChatRepository>();
    try {
      final membersResult = await repo.getThreadParticipants(widget.threadId);
      final ordersResult  = await repo.getActiveOrders();
      if (!mounted) return;
      setState(() {
        if (membersResult is AppSuccess<List<Profile>>) {
          _threadMembers = membersResult.data;
        }
        if (ordersResult is AppSuccess<List<({String id, String displayName})>>) {
          _activeOrders = ordersResult.data;
        }
      });
    } catch (_) {
      // Mention data is best-effort; silently ignore failures
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  bool _canManage(BuildContext context) {
    final state = context.read<AuthCubit>().state;
    if (state is! AuthAuthenticated) return false;
    final role = state.profile.role;
    return role == UserRole.verifier || role == UserRole.manager;
  }

  bool get _isCreator =>
      widget.createdBy != null &&
      widget.createdBy == Supabase.instance.client.auth.currentUser?.id;

  Profile? _otherParticipant() {
    if (!widget.isDirect) return null;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    try {
      return _threadMembers.firstWhere((m) => m.id != myId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteThread(BuildContext context) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المحادثة'),
        content: Text(
            'هل تريد حذف محادثة "${widget.threadTitle}" نهائياً؟\nسيتم حذف جميع الرسائل ولا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await sl<ChatRepository>().deleteThread(widget.threadId);
      if (mounted) nav.pop(true);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _otherParticipant();
    return BlocConsumer<ChatThreadCubit, ChatThreadState>(
      listener: (context, state) {
        if (state is ChatThreadLoaded) {
          if (!_initialized && state.pendingInitialText != null) {
            // Signal the input bar to pre-fill text via notifier pattern
            _initialized = true;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
        if (state is ChatThreadError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: other != null
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(profile: other, isSelf: false),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.threadTitle),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new, size: 14),
                      ],
                    ),
                  )
                : Text(widget.threadTitle),
            actions: [
              if (!widget.isDirect && _canManage(context))
                IconButton(
                  icon: const Icon(Icons.group),
                  tooltip: 'الأعضاء',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ThreadMembersScreen(
                        threadId: widget.threadId,
                        threadTitle: widget.threadTitle,
                        createdBy: widget.createdBy ?? '',
                      ),
                    ),
                  ),
                ),
              if (_isCreator && _canManage(context))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'delete') _deleteThread(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('حذف المحادثة', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              // Urgent entry banner
              if (widget.isUrgentEntry)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.orange.withAlpha(40),
                  child: Row(
                    children: [
                      Icon(Icons.priority_high, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هذه الرسالة مرتبطة بطلب — سيُعلَم المسؤولون',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Messages list — only rebuilds when cubit emits new state
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (state is ChatThreadLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is ChatThreadLoaded) {
                      if (state.messages.isEmpty) {
                        return const Center(
                          child: Text('لا توجد رسائل بعد',
                              style: TextStyle(color: Colors.grey)),
                        );
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: state.messages.length,
                        itemBuilder: (_, i) {
                          final msg = state.messages[i];
                          return ChatMessageBubble(
                            message: msg,
                            onAcknowledge: msg.isUrgent && !msg.isAcknowledged
                                ? () => context
                                    .read<ChatThreadCubit>()
                                    .acknowledgeMessage(msg.id)
                                : null,
                            onReply: (m) => _replyNotifier.value = m,
                            onReactToggle: (messageId, emoji) => context
                                .read<ChatThreadCubit>()
                                .addReaction(messageId, emoji),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),

              // Input bar — isolated StatefulWidget; typing never rebuilds the ListView
              _ChatInputBar(
                threadId: widget.threadId,
                threadMembers: _threadMembers,
                activeOrders: _activeOrders,
                replyNotifier: _replyNotifier,
                initialText:
                    state is ChatThreadLoaded ? state.pendingInitialText : null,
                isUrgentEntry: widget.isUrgentEntry,
                isDirect: widget.isDirect,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Input bar — all input state lives here, never triggers ListView rebuilds ──

class _ChatInputBar extends StatefulWidget {
  final String threadId;
  final List<Profile> threadMembers;
  final List<({String id, String displayName})> activeOrders;
  final ValueNotifier<ChatMessage?> replyNotifier;
  final String? initialText;
  final bool isUrgentEntry;
  final bool isDirect;

  const _ChatInputBar({
    required this.threadId,
    required this.threadMembers,
    required this.activeOrders,
    required this.replyNotifier,
    this.initialText,
    this.isUrgentEntry = false,
    this.isDirect = false,
  });

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _textInitialized = false;

  String _mentionQuery = '';
  bool _showMentionPicker = false;
  bool _isUrgentOverride = false;

  String? _pendingUserMentionId;
  String? _pendingUserMentionText;
  String? _pendingOrderMentionId;
  String? _pendingOrderMentionText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_ChatInputBar old) {
    super.didUpdateWidget(old);
    if (!_textInitialized && widget.initialText != null) {
      _controller.text = widget.initialText!;
      _controller.selection =
          TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
      _textInitialized = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final beforeCursor = text.substring(0, sel.baseOffset);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex == -1) {
      if (_showMentionPicker) setState(() => _showMentionPicker = false);
      return;
    }
    final charBefore = atIndex > 0 ? text[atIndex - 1] : ' ';
    if (charBefore != ' ' && atIndex != 0) {
      if (_showMentionPicker) setState(() => _showMentionPicker = false);
      return;
    }
    final query = beforeCursor.substring(atIndex + 1).toLowerCase();
    if (query.contains(' ')) {
      if (_showMentionPicker) setState(() => _showMentionPicker = false);
      return;
    }
    setState(() {
      _mentionQuery = query;
      _showMentionPicker = true;
    });
  }

  void _selectMention({
    String? userId,
    String? userName,
    String? orderId,
    String? orderName,
  }) {
    final text = _controller.text;
    final sel = _controller.selection;
    final beforeCursor =
        text.substring(0, sel.isValid ? sel.baseOffset : text.length);
    final atIndex = beforeCursor.lastIndexOf('@');
    final after = sel.isValid ? text.substring(sel.baseOffset) : '';
    final mentionLabel = userName ?? orderName ?? '';
    final newText = '${text.substring(0, atIndex)}@$mentionLabel $after';
    setState(() {
      _showMentionPicker = false;
      _pendingUserMentionId = (userId != null && userId.isNotEmpty) ? userId : null;
      _pendingUserMentionText = userName;
      _pendingOrderMentionId = orderId;
      _pendingOrderMentionText = orderName;
    });
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIndex + mentionLabel.length + 2),
    );
    _focusNode.requestFocus();
  }

  void _triggerMentionPicker() {
    final text = _controller.text;
    final offset =
        _controller.selection.isValid ? _controller.selection.baseOffset : text.length;
    final prefix = text.substring(0, offset);
    final suffix = text.substring(offset);
    final sep = (prefix.isNotEmpty && !prefix.endsWith(' ')) ? ' ' : '';
    _controller.value = TextEditingValue(
      text: '$prefix$sep@$suffix',
      selection: TextSelection.collapsed(offset: offset + sep.length + 1),
    );
    _focusNode.requestFocus();
  }

  void _send(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final reply = widget.replyNotifier.value;
    context.read<ChatThreadCubit>().sendMessage(
      text,
      userMentionId: _pendingUserMentionId,
      userMentionText: _pendingUserMentionText,
      orderMentionId: _pendingOrderMentionId,
      orderMentionText: _pendingOrderMentionText,
      isUrgent: _isUrgentOverride ? true : null,
      replyToId: reply?.id,
      replyToContent: reply?.content,
      replyToSender: reply?.senderName,
    );
    setState(() {
      _pendingUserMentionId = _pendingUserMentionText = null;
      _pendingOrderMentionId = _pendingOrderMentionText = null;
      _showMentionPicker = false;
      _isUrgentOverride = false;
    });
    widget.replyNotifier.value = null;
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    if (widget.threadMembers.isEmpty) return;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (widget.isDirect) {
      Profile? other;
      try {
        other = widget.threadMembers.firstWhere((m) => m.id != myId);
      } catch (_) {}
      _launchWhatsApp(context, other);
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _WhatsAppMemberSheet(members: widget.threadMembers),
      );
    }
  }

  Future<void> _launchWhatsApp(BuildContext context, Profile? profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final raw = profile?.phone;
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('لا يوجد رقم واتساب لهذا المستخدم')),
        );
      }
      return;
    }
    final number = raw.replaceAll(RegExp(r'[\s\-\+]'), '');
    final uri = Uri.parse('https://wa.me/$number');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('تعذّر فتح واتساب')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Urgent active banner
        if (_isUrgentOverride)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.orange.withAlpha(40),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ستُرسل هذه الرسالة كعاجلة — سيُنبَّه الجميع',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isUrgentOverride = false),
                  child: Icon(Icons.close, size: 16, color: Colors.orange.shade700),
                ),
              ],
            ),
          ),

        // Reply-to strip
        ValueListenableBuilder<ChatMessage?>(
          valueListenable: widget.replyNotifier,
          builder: (context, replyTarget, _) {
            if (replyTarget == null) return const SizedBox.shrink();
            return Container(
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surface : Colors.grey.shade50,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replyTarget.senderName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          replyTarget.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => widget.replyNotifier.value = null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            );
          },
        ),

        // Mention suggestions panel
        if (_showMentionPicker)
          MentionSuggestions(
            query: _mentionQuery,
            members: widget.threadMembers,
            orders: widget.activeOrders,
            onSelectUser: (id, name) => _selectMention(userId: id, userName: name),
            onSelectOrder: (id, name) => _selectMention(orderId: id, orderName: name),
          ),

        // Input row
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 22),
                  onPressed: () => _openWhatsApp(context),
                  color: theme.hintColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? theme.colorScheme.surface.withAlpha(200)
                          : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      hintStyle: TextStyle(color: theme.hintColor),
                    ),
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.alternate_email, size: 22),
                  onPressed: _triggerMentionPicker,
                  color: theme.hintColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: Icon(
                    Icons.priority_high,
                    size: 22,
                    color: _isUrgentOverride ? Colors.orange.shade700 : theme.hintColor,
                  ),
                  onPressed: () =>
                      setState(() => _isUrgentOverride = !_isUrgentOverride),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton.filled(
                  onPressed: () => _send(context),
                  icon: Transform.flip(
                    flipX: Directionality.of(context) == TextDirection.rtl,
                    child: const Icon(Icons.send),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── WhatsApp member sheet ─────────────────────────────────────────────────────

class _WhatsAppMemberSheet extends StatelessWidget {
  final List<Profile> members;
  const _WhatsAppMemberSheet({required this.members});

  @override
  Widget build(BuildContext context) {
    final withPhone = members.where((m) => m.phone?.isNotEmpty == true).toList();
    final noPhone = members.where((m) => m.phone?.isNotEmpty != true).toList();
    final all = [...withPhone, ...noPhone];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('أرسل ملفاً عبر واتساب',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('لا يوجد أعضاء في هذه المحادثة',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: all.length,
                itemBuilder: (_, i) {
                  final member = all[i];
                  final hasPhone = member.phone?.isNotEmpty == true;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                          member.fullName.isNotEmpty ? member.fullName[0] : '?'),
                    ),
                    title: Text(
                      member.fullName,
                      style: TextStyle(
                          color: hasPhone ? null : Theme.of(context).hintColor),
                    ),
                    subtitle: Text(
                      hasPhone ? member.phone! : 'لا يوجد رقم',
                      style: TextStyle(
                          color: hasPhone
                              ? Theme.of(context).hintColor
                              : Theme.of(context).hintColor.withAlpha(150)),
                    ),
                    onTap: hasPhone
                        ? () {
                            Navigator.pop(context);
                            final number =
                                member.phone!.replaceAll(RegExp(r'[\s\-\+]'), '');
                            launchUrl(Uri.parse('https://wa.me/$number'),
                                mode: LaunchMode.externalApplication);
                          }
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
