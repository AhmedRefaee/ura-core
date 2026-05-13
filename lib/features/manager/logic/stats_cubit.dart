import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../data/stats_models.dart';
import '../data/stats_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class StatsState extends Equatable {
  const StatsState();
  @override
  List<Object?> get props => [];
}

class StatsInitial extends StatsState {}

class StatsLoading extends StatsState {}

class StatsLoaded extends StatsState {
  final StatsData data;
  final String period;
  const StatsLoaded({required this.data, required this.period});
  @override
  List<Object?> get props => [data, period];
}

class StatsError extends StatsState {
  final String message;
  const StatsError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class StatsCubit extends Cubit<StatsState> {
  final StatsRepository _repo;

  StatsCubit(this._repo) : super(StatsInitial());

  Future<void> load(String period) async {
    logger.d('StatsCubit → load: $period');
    emit(StatsLoading());
    final (start, end) = _getDateRange(period);
    final result = await _repo.fetchAll(start, end);
    switch (result) {
      case AppSuccess(:final data):
        emit(StatsLoaded(data: data, period: period));
      case AppFailure(:final error):
        logger.e('StatsCubit → load failed: ${error.message}');
        emit(StatsError(error.message));
    }
  }

  (DateTime, DateTime) _getDateRange(String period) {
    final now = DateTime.now();
    final start = switch (period) {
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      '3m' => DateTime(now.year, now.month - 3, now.day),
      '6m' => DateTime(now.year, now.month - 6, now.day),
      '1y' => DateTime(now.year - 1, now.month, now.day),
      _ => now.subtract(const Duration(days: 30)),
    };
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return (start, end);
  }
}
