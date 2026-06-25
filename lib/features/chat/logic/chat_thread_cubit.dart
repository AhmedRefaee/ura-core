import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_message.dart';
import '../data/chat_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ─── States ──────────────────────────────────────────────────────────────────

abstract class ChatThreadState extends Equatable {
  const ChatThreadState();
  @override
  List<Object?> get props => [];
}

class ChatThreadLoading extends ChatThreadState {}

class ChatThreadLoaded extends ChatThreadState {
  final List<ChatMessage> messages;
  final String? pendingInitialText;
  const ChatThreadLoaded({required this.messages, this.pendingInitialText});
  @override
  List<Object?> get props => [messages, pendingInitialText];
}

class ChatThreadError extends ChatThreadState {
  final String message;
  const ChatThreadError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── Cubit ───────────────────────────────────────────────────────────────────

class ChatThreadCubit extends Cubit<ChatThreadState>
    with SafeEmit<ChatThreadState> {
  final ChatRepository _repo;
  final String threadId;
  final String? initialText;
  final bool isUrgentEntry;
  final String? mentionedOrderId;
  final String? mentionedOrderTitle;

  StreamSubscription<List<ChatMessage>>? _sub;
  RealtimeChannel? _reactionChannel;
  List<ChatMessage> _messages = [];
  Map<String, List<ChatMessageReaction>> _reactions = {};

  ChatThreadCubit(
    this._repo, {
    required this.threadId,
    this.initialText,
    this.isUrgentEntry = false,
    this.mentionedOrderId,
    this.mentionedOrderTitle,
  }) : super(ChatThreadLoading());

  void subscribe() {
    logger.d('ChatThreadCubit → subscribe: $threadId');
    _sub = _repo
        .subscribeToThread(threadId)
        .listen(
          (messages) {
            _messages = messages;
            _emitMerged();
          },
          onError: (Object e, StackTrace st) {
            logger.e(
              'ChatThreadCubit → stream error',
              error: e,
              stackTrace: st,
            );
            safeEmit(ChatThreadError(ErrorHandler.handle(e).message));
          },
        );
    _loadReactions();
    _reactionChannel ??= Supabase.instance.client
        .channel('chat-reactions-$threadId-$hashCode')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_message_reactions',
          callback: (_) => _loadReactions(),
        )
        .subscribe();
  }

  Future<void> _loadReactions() async {
    final result = await _repo.getReactionsForThread(threadId);
    if (result is AppSuccess<Map<String, List<ChatMessageReaction>>>) {
      _reactions = result.data;
      _emitMerged();
    }
  }

  void _emitMerged() {
    final merged = _messages
        .map((m) => m.copyWith(reactions: _reactions[m.id] ?? []))
        .toList();
    final current = state;
    final pending = current is ChatThreadLoaded
        ? current.pendingInitialText
        : initialText;
    if (!isClosed) {
      safeEmit(ChatThreadLoaded(messages: merged, pendingInitialText: pending));
    }
  }

  Future<void> sendMessage(
    String content, {
    String? userMentionId,
    String? userMentionText,
    String? orderMentionId,
    String? orderMentionText,
    bool? isUrgent,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    logger.d(
      'ChatThreadCubit → sendMessage, urgent=${isUrgent ?? isUrgentEntry}',
    );
    final result = await _repo.sendMessage(
      threadId: threadId,
      content: content,
      orderMentionId: orderMentionId ?? mentionedOrderId,
      orderMentionText: orderMentionText ?? mentionedOrderTitle,
      userMentionId: userMentionId,
      userMentionText: userMentionText,
      isUrgent: isUrgent ?? isUrgentEntry,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSender: replyToSender,
    );
    switch (result) {
      case AppSuccess():
        final current = state;
        if (current is ChatThreadLoaded && current.pendingInitialText != null) {
          safeEmit(
            ChatThreadLoaded(
              messages: current.messages,
              pendingInitialText: null,
            ),
          );
        }
      case AppFailure(:final error):
        logger.e('ChatThreadCubit → sendMessage failed: ${error.message}');
        if (!isClosed) safeEmit(ChatThreadError(error.message));
    }
  }

  Future<void> acknowledgeMessage(String messageId) async {
    logger.d('ChatThreadCubit → acknowledgeMessage: $messageId');
    final result = await _repo.acknowledgeMessage(messageId);
    if (result is AppFailure) {
      logger.e(
        'ChatThreadCubit → acknowledgeMessage failed: ${result.error.message}',
      );
    }
  }

  Future<void> addReaction(String messageId, String emoji) async {
    logger.d('ChatThreadCubit → addReaction: $messageId $emoji');
    final myId = Supabase.instance.client.auth.currentUser?.id;
    // Optimistic update
    final existing = _reactions[messageId] ?? [];
    final alreadyReacted = existing.any(
      (r) => r.emoji == emoji && r.userId == myId,
    );
    if (alreadyReacted) {
      await removeReaction(messageId, emoji);
      return;
    }
    _reactions[messageId] = [
      ...existing,
      ChatMessageReaction(emoji: emoji, userId: myId ?? ''),
    ];
    _emitMerged();
    final result = await _repo.addReaction(messageId, emoji);
    if (result is AppFailure) {
      // Rollback optimistic update
      _reactions[messageId] = existing;
      _emitMerged();
    }
  }

  Future<void> removeReaction(String messageId, String emoji) async {
    logger.d('ChatThreadCubit → removeReaction: $messageId $emoji');
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final existing = _reactions[messageId] ?? [];
    // Optimistic update
    _reactions[messageId] = existing
        .where((r) => !(r.emoji == emoji && r.userId == myId))
        .toList();
    _emitMerged();
    final result = await _repo.removeReaction(messageId, emoji);
    if (result is AppFailure) {
      _reactions[messageId] = existing;
      _emitMerged();
    }
  }

  @override
  Future<void> close() async {
    await _reactionChannel?.unsubscribe();
    await _sub?.cancel();
    return super.close();
  }
}
