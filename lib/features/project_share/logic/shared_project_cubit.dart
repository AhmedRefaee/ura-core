import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../data/project_share_repository.dart';
import '../models/shared_project.dart';

sealed class SharedProjectState extends Equatable {
  const SharedProjectState();
  @override
  List<Object?> get props => [];
}

final class SharedProjectLoading extends SharedProjectState {
  const SharedProjectLoading();
}

final class SharedProjectLoaded extends SharedProjectState {
  final SharedProject project;

  /// The سندات filed through this link (only when it allows filing).
  final List<SharedReceipt> receipts;
  const SharedProjectLoaded(this.project, {this.receipts = const []});
  @override
  List<Object?> get props => [project, receipts];
}

/// Unknown, revoked or expired -- the server doesn't say which, by design.
final class SharedProjectInvalid extends SharedProjectState {
  const SharedProjectInvalid();
}

final class SharedProjectError extends SharedProjectState {
  final String message;
  const SharedProjectError(this.message);
  @override
  List<Object?> get props => [message];
}

class SharedProjectCubit extends Cubit<SharedProjectState> {
  final ProjectShareRepository _repo;
  final String token;

  SharedProjectCubit(this._repo, this.token) : super(const SharedProjectLoading());

  Future<void> load() async {
    emit(const SharedProjectLoading());
    final result = await _repo.fetchShared(token);
    switch (result) {
      case AppSuccess(data: final p?):
        emit(SharedProjectLoaded(p, receipts: p.canSubmit ? await _fetchReceipts() : const []));
      case AppSuccess():
        emit(const SharedProjectInvalid());
      case AppFailure(:final error):
        emit(SharedProjectError(error.message));
    }
  }

  /// After filing a سند, or to pick up a decision made in the meantime.
  Future<void> refreshReceipts() async {
    final current = state;
    if (current is! SharedProjectLoaded || !current.project.canSubmit) return;
    final receipts = await _fetchReceipts();
    if (!isClosed) emit(SharedProjectLoaded(current.project, receipts: receipts));
  }

  Future<List<SharedReceipt>> _fetchReceipts() async => switch (await _repo.fetchSharedReceipts(token)) {
        AppSuccess(:final data) => data,
        AppFailure() => const <SharedReceipt>[],
      };
}
