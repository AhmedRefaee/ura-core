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
  const SharedProjectLoaded(this.project);
  @override
  List<Object?> get props => [project];
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
    emit(switch (result) {
      AppSuccess(data: final p?) => SharedProjectLoaded(p),
      AppSuccess() => const SharedProjectInvalid(),
      AppFailure(:final error) => SharedProjectError(error.message),
    });
  }
}
