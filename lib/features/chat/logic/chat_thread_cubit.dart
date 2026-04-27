import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_message.dart';
import '../data/chat_repository.dart';

// ─── States ──────────────────────────────────────────────────────────────────

abstract class ChatThreadState extends Equatable {
  const ChatThreadState();
  @override
  List<Object?> get props => [];
}

class ChatThreadLoading extends ChatThreadState {}

class ChatThreadLoaded extends ChatThreadState {
  final List<ChatMessage> messages;
  final String? pendingInitialText; // cleared after first send
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

class ChatThreadCubit extends Cubit<ChatThreadState> {
  final ChatRepository _repo;
  final String threadId;
  final String? initialText;
  final bool isUrgentEntry;
  final String? mentionedOrderId;
  final String? mentionedOrderTitle;

  StreamSubscription<List<ChatMessage>>? _sub;

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
    _sub = _repo.subscribeToThread(threadId).listen(
      (messages) {
        final current = state;
        final pending = current is ChatThreadLoaded ? current.pendingInitialText : initialText;
        emit(ChatThreadLoaded(messages: messages, pendingInitialText: pending));
      },
      onError: (Object e, StackTrace st) {
        logger.e('ChatThreadCubit → stream error', error: e, stackTrace: st);
        emit(ChatThreadError(e.toString()));
      },
    );
  }

  Future<void> sendMessage(
    String content, {
    String? userMentionId,
    String? userMentionText,
    String? orderMentionId,
    String? orderMentionText,
    bool? isUrgent, // overrides isUrgentEntry when provided
  }) async {
    logger.d('ChatThreadCubit → sendMessage, urgent=${isUrgent ?? isUrgentEntry}');
    try {
      await _repo.sendMessage(
        threadId: threadId,
        content: content,
        orderMentionId: orderMentionId ?? mentionedOrderId,
        orderMentionText: orderMentionText ?? mentionedOrderTitle,
        userMentionId: userMentionId,
        userMentionText: userMentionText,
        isUrgent: isUrgent ?? isUrgentEntry,
      );
      // Clear the initial text hint after the first successful send
      final current = state;
      if (current is ChatThreadLoaded && current.pendingInitialText != null) {
        emit(ChatThreadLoaded(messages: current.messages, pendingInitialText: null));
      }
    } catch (e, st) {
      logger.e('ChatThreadCubit → sendMessage failed', error: e, stackTrace: st);
      emit(ChatThreadError(e.toString()));
    }
  }

  Future<void> acknowledgeMessage(String messageId) async {
    logger.d('ChatThreadCubit → acknowledgeMessage: $messageId');
    try {
      await _repo.acknowledgeMessage(messageId);
    } catch (e, st) {
      logger.e('ChatThreadCubit → acknowledgeMessage failed', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
