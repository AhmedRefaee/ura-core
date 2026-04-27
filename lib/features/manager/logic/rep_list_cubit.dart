import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';
import '../data/manager_repository.dart';

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

/// A rep profile paired with their most recent order status.
class RepWithStatus extends Equatable {
  final Profile profile;
  final OrderStatus? latestStatus;
  const RepWithStatus({required this.profile, this.latestStatus});
  @override
  List<Object?> get props => [profile, latestStatus];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class RepListCubit extends Cubit<RepListState> {
  final ManagerRepository _repo;

  RepListCubit(this._repo) : super(RepListInitial());

  Future<void> load() async {
    logger.d('RepListCubit → load');
    emit(RepListLoading());
    try {
      final results = await Future.wait([
        _repo.fetchUsersByRole('rep'),
        _repo.fetchLatestOrderStatusByRep(),
      ]);
      final reps = results[0] as List<Profile>;
      final statusMap = results[1] as Map<String, OrderStatus>;

      final repList = reps
          .map((r) => RepWithStatus(
                profile: r,
                latestStatus: statusMap[r.id],
              ))
          .toList();

      emit(RepListLoaded(repList));
    } catch (e, st) {
      logger.e('RepListCubit → load failed', error: e, stackTrace: st);
      emit(RepListError(e.toString()));
    }
  }
}
