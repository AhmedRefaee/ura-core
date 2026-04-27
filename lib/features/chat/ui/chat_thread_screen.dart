import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/di/injection.dart';
import '../../../features/auth/logic/auth_cubit.dart';
import '../../../features/auth/logic/auth_state.dart';
import '../../../shared/models/profile.dart';
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
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _initialized = false;

  // Mention picker
  List<Profile> _threadMembers = [];
  List<({String id, String displayName})> _activeOrders = [];
  String _mentionQuery = '';
  bool _showMentionPicker = false;

  // Per-message urgent flag (user can toggle before sending)
  bool _isUrgentOverride = false;

  // Pending inline mention (user OR order — one at a time)
  String? _pendingUserMentionId;
  String? _pendingUserMentionText;
  String? _pendingOrderMentionId;
  String? _pendingOrderMentionText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadMentionData();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMentionData() async {
    final repo = sl<ChatRepository>();
    try {
      final results = await Future.wait([
        repo.getThreadParticipants(widget.threadId), // only this thread's members
        repo.getActiveOrders(),
      ]);
      if (mounted) {
        setState(() {
          _threadMembers = results[0] as List<Profile>;
          _activeOrders = results[1] as List<({String id, String displayName})>;
        });
      }
    } catch (_) {
      // Mention data is best-effort; silently ignore failures
    }
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
    // Only trigger when @ appears at start or after a space
    final charBefore = atIndex > 0 ? text[atIndex - 1] : ' ';
    if (charBefore != ' ' && atIndex != 0) {
      if (_showMentionPicker) setState(() => _showMentionPicker = false);
      return;
    }
    final query = beforeCursor.substring(atIndex + 1).toLowerCase();
    // A space in the query means the mention token is already complete — close picker
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
    final beforeCursor = text.substring(0, sel.isValid ? sel.baseOffset : text.length);
    final atIndex = beforeCursor.lastIndexOf('@');
    final after = sel.isValid ? text.substring(sel.baseOffset) : '';
    final mentionLabel = userName ?? orderName ?? '';
    final newText = '${text.substring(0, atIndex)}@$mentionLabel $after';
    setState(() {
      _showMentionPicker = false;
      // Empty string signals @all — store null so no invalid UUID reaches the DB
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
    final offset = _controller.selection.isValid
        ? _controller.selection.baseOffset
        : text.length;
    final prefix = text.substring(0, offset);
    final suffix = text.substring(offset);
    final sep = (prefix.isNotEmpty && !prefix.endsWith(' ')) ? ' ' : '';
    _controller.value = TextEditingValue(
      text: '$prefix$sep@$suffix',
      selection: TextSelection.collapsed(offset: offset + sep.length + 1),
    );
    _focusNode.requestFocus();
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

  Future<void> _deleteThread() async {
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
      if (mounted) Navigator.pop(context, true); // signals hub to refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الحذف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  void _send(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<ChatThreadCubit>().sendMessage(
      text,
      userMentionId: _pendingUserMentionId,
      userMentionText: _pendingUserMentionText,
      orderMentionId: _pendingOrderMentionId,
      orderMentionText: _pendingOrderMentionText,
      isUrgent: _isUrgentOverride ? true : null,
    );
    setState(() {
      _pendingUserMentionId = _pendingUserMentionText = null;
      _pendingOrderMentionId = _pendingOrderMentionText = null;
      _showMentionPicker = false;
      _isUrgentOverride = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatThreadCubit, ChatThreadState>(
      listener: (context, state) {
        if (state is ChatThreadLoaded) {
          // Pre-fill with initialText on first load
          if (!_initialized && state.pendingInitialText != null) {
            _controller.text = state.pendingInitialText!;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
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
            title: Text(widget.threadTitle),
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
                    if (value == 'delete') _deleteThread();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('حذف المحادثة',
                              style: TextStyle(color: Colors.red)),
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
                  color: Colors.orange.shade100,
                  child: Row(
                    children: [
                      Icon(Icons.priority_high, size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هذه الرسالة مرتبطة بطلب — سيُعلَم المسؤولون',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Messages list
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (state is ChatThreadLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is ChatThreadLoaded) {
                      if (state.messages.isEmpty) {
                        return const Center(
                          child: Text(
                            'لا توجد رسائل بعد',
                            style: TextStyle(color: Colors.grey),
                          ),
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
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),

              // Urgent active banner
              if (_isUrgentOverride)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'ستُرسل هذه الرسالة كعاجلة — سيُنبَّه الجميع',
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade800),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _isUrgentOverride = false),
                        child: Icon(Icons.close,
                            size: 16, color: Colors.orange.shade800),
                      ),
                    ],
                  ),
                ),

              // Mention suggestions panel
              if (_showMentionPicker)
                MentionSuggestions(
                  query: _mentionQuery,
                  members: _threadMembers,
                  orders: _activeOrders,
                  onSelectUser: (id, name) =>
                      _selectMention(userId: id, userName: name),
                  onSelectOrder: (id, name) =>
                      _selectMention(orderId: id, orderName: name),
                ),

              // Input row
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
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
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'خيارات',
                        onSelected: (value) {
                          if (value == 'urgent') {
                            setState(() => _isUrgentOverride = !_isUrgentOverride);
                          } else if (value == 'mention') {
                            _triggerMentionPicker();
                          }
                        },
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem(
                            value: 'urgent',
                            checked: _isUrgentOverride,
                            child: const Text('رسالة عاجلة'),
                          ),
                          const PopupMenuItem(
                            value: 'mention',
                            child: Row(
                              children: [
                                Text('@',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                SizedBox(width: 8),
                                Text('ذكر شخص أو طلب'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      IconButton.filled(
                        onPressed: () => _send(context),
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
