import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_thread.dart';
import '../data/chat_repository.dart';

// ─── States ──────────────────────────────────────────────────────────────────

abstract class ChatThreadsState extends Equatable {
  const ChatThreadsState();
  @override
  List<Object?> get props => [];
}

class ChatThreadsInitial extends ChatThreadsState {}

class ChatThreadsLoading extends ChatThreadsState {}

class ChatThreadsLoaded extends ChatThreadsState {
  final List<ChatThread> threads;
  const ChatThreadsLoaded(this.threads);
  @override
  List<Object?> get props => [threads];
}

class ChatThreadsError extends ChatThreadsState {
  final String message;
  const ChatThreadsError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── Cubit ───────────────────────────────────────────────────────────────────

class ChatThreadsCubit extends Cubit<ChatThreadsState> {
  final ChatRepository _repo;
  RealtimeChannel? _channel;

  ChatThreadsCubit(this._repo) : super(ChatThreadsInitial());

  Future<void> loadThreads() async {
    logger.d('ChatThreadsCubit → loadThreads');
    emit(ChatThreadsLoading());
    final result = await _repo.getThreads();
    if (!isClosed) {
      switch (result) {
        case AppSuccess(:final data):
          final sorted = [...data]
            ..sort((a, b) => (b.lastMessageAt ?? b.createdAt)
                .compareTo(a.lastMessageAt ?? a.createdAt));
          final withMessages = sorted.where((t) => t.lastMessageAt != null).toList();
          emit(ChatThreadsLoaded(withMessages));
          _subscribeToChanges();
        case AppFailure(:final error):
          logger.e('ChatThreadsCubit → loadThreads failed: ${error.message}');
          emit(ChatThreadsError(error.message));
      }
    }
  }

  void _subscribeToChanges() {
    _channel ??= Supabase.instance.client
        .channel('chat-threads-$hashCode')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _silentRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_threads',
          callback: (_) => _silentRefresh(),
        )
        .subscribe();
  }

  Future<void> _silentRefresh() async {
    final result = await _repo.getThreads();
    if (!isClosed && result is AppSuccess<List<ChatThread>>) {
      final sorted = [...result.data]
        ..sort((a, b) => (b.lastMessageAt ?? b.createdAt)
            .compareTo(a.lastMessageAt ?? a.createdAt));
      final withMessages = sorted.where((t) => t.lastMessageAt != null).toList();
      emit(ChatThreadsLoaded(withMessages));
    }
  }

  Future<String?> createThread(String title) async {
    logger.d('ChatThreadsCubit → createThread: $title');
    final result = await _repo.createThread(title);
    switch (result) {
      case AppSuccess(:final data):
        await loadThreads();
        return data;
      case AppFailure(:final error):
        logger.e('ChatThreadsCubit → createThread failed: ${error.message}');
        if (!isClosed) emit(ChatThreadsError(error.message));
        return null;
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
