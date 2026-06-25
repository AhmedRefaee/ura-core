import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ── States ────────────────────────────────────────────────────────────────────

abstract class RepListState extends Equatable {
  const RepListState();
  @override
  List<Object?> get props => [];
}

class RepListInitial extends RepListState {}

class RepListLoading extends RepListState {}

class RepListLoaded extends RepListState {
  final List<RepWithStatus> reps;
  const RepListLoaded(this.reps);
  @override
  List<Object?> get props => [reps];
}

class RepListError extends RepListState {
  final String message;
  const RepListError(this.message);
  @override
  List<Object?> get props => [message];
}

class RepWithStatus extends Equatable {
  final Profile profile;
  final OrderStatus? latestStatus;
  const RepWithStatus({required this.profile, this.latestStatus});
  @override
  List<Object?> get props => [profile, latestStatus];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class RepListCubit extends Cubit<RepListState> with SafeEmit<RepListState> {
  final ManagerRepository _repo;

  RepListCubit(this._repo) : super(RepListInitial());

  Future<void> load() async {
    logger.d('RepListCubit → load');
    safeEmit(RepListLoading());

    final results = await Future.wait([
      _repo.fetchUsersByRole('rep'),
      _repo.fetchLatestOrderStatusByRep(),
    ]);

    if (isClosed) return;

    final repsError = results[0].failureOrNull;
    if (repsError != null) {
      logger.e('RepListCubit → load failed: ${repsError.message}');
      safeEmit(RepListError(repsError.message));
      return;
    }
    final statusError = results[1].failureOrNull;
    if (statusError != null) {
      logger.e('RepListCubit → load failed: ${statusError.message}');
      safeEmit(RepListError(statusError.message));
      return;
    }

    final reps = (results[0] as AppSuccess<List<Profile>>).data;
    final statusMap = (results[1] as AppSuccess<Map<String, OrderStatus>>).data;

    safeEmit(
      RepListLoaded(
        reps
            .map(
              (r) => RepWithStatus(profile: r, latestStatus: statusMap[r.id]),
            )
            .toList(),
      ),
    );
  }
}
