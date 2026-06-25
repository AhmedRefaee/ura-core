import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/profile.dart';
import '../data/chat_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ─── States ──────────────────────────────────────────────────────────────────

abstract class ChatDirectoryState extends Equatable {
  const ChatDirectoryState();
  @override
  List<Object?> get props => [];
}

class ChatDirectoryInitial extends ChatDirectoryState {}

class ChatDirectoryLoading extends ChatDirectoryState {}

class ChatDirectoryLoaded extends ChatDirectoryState {
  final Map<UserRole, List<Profile>> usersByRole;
  const ChatDirectoryLoaded(this.usersByRole);
  @override
  List<Object?> get props => [usersByRole];
}

class ChatDirectoryError extends ChatDirectoryState {
  final String message;
  const ChatDirectoryError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── Cubit ───────────────────────────────────────────────────────────────────

class ChatDirectoryCubit extends Cubit<ChatDirectoryState>
    with SafeEmit<ChatDirectoryState> {
  final ChatRepository _repo;
  StreamSubscription<List<Profile>>? _sub;

  // Display order for role sections
  static const _roleOrder = [
    UserRole.manager,
    UserRole.verifier,
    UserRole.storageActor,
    UserRole.rep,
  ];

  ChatDirectoryCubit(this._repo) : super(ChatDirectoryInitial());

  Future<void> load() async {
    logger.d('ChatDirectoryCubit → load');
    safeEmit(ChatDirectoryLoading());

    final result = await _repo.getUsers();
    if (isClosed) return;
    switch (result) {
      case AppSuccess(:final data):
        safeEmit(ChatDirectoryLoaded(_group(data)));
        _subscribe();
      case AppFailure(:final error):
        logger.e('ChatDirectoryCubit → load failed: ${error.message}');
        safeEmit(ChatDirectoryError(error.message));
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _repo.subscribeToApprovedProfiles().listen(
      (profiles) {
        if (!isClosed) {
          logger.d('ChatDirectoryCubit → profiles updated: ${profiles.length}');
          safeEmit(ChatDirectoryLoaded(_group(profiles)));
        }
      },
      onError: (Object e) {
        logger.e('ChatDirectoryCubit → stream error: $e');
      },
    );
  }

  Map<UserRole, List<Profile>> _group(List<Profile> profiles) {
    final map = <UserRole, List<Profile>>{for (final r in _roleOrder) r: []};
    for (final p in profiles) {
      if (p.role != null) map[p.role!]?.add(p);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.fullName.compareTo(b.fullName));
    }
    return map;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
