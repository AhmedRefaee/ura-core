import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    try {
      final threads = await _repo.getThreads();
      emit(ChatThreadsLoaded(threads));
    } catch (e, st) {
      logger.e('ChatThreadsCubit → loadThreads failed', error: e, stackTrace: st);
      emit(ChatThreadsError(e.toString()));
    }
  }

  /// Creates a new thread and returns its id, then reloads the list.
  Future<String?> createThread(String title) async {
    logger.d('ChatThreadsCubit → createThread: $title');
    try {
      final id = await _repo.createThread(title);
      await loadThreads();
      return id;
    } catch (e, st) {
      logger.e('ChatThreadsCubit → createThread failed', error: e, stackTrace: st);
      emit(ChatThreadsError(e.toString()));
      return null;
    }
  }
}
