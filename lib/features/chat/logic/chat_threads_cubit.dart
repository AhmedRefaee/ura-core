import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  ChatThreadsCubit(this._repo) : super(ChatThreadsInitial());

  Future<void> loadThreads() async {
    logger.d('ChatThreadsCubit → loadThreads');
    emit(ChatThreadsLoading());
    final result = await _repo.getThreads();
    if (!isClosed) {
      switch (result) {
        case AppSuccess(:final data):
          emit(ChatThreadsLoaded(data));
        case AppFailure(:final error):
          logger.e('ChatThreadsCubit → loadThreads failed: ${error.message}');
          emit(ChatThreadsError(error.message));
      }
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
}
