import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import 'stats_models.dart';

class StatsRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AppResult<GlobalStatsSummary>> fetchGlobalOverview(DateTime start, DateTime end) async {
    try {
      logger.d('StatsRepository → fetchGlobalOverview: $start to $end');
      final result = await _supabase.rpc('get_global_stats_overview', params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      });
      if (result == null) throw Exception('No data returned from get_global_stats_overview');
      return AppSuccess(GlobalStatsSummary.fromJson(result as Map<String, dynamic>));
    } catch (e, st) {
      logger.e('StatsRepository → fetchGlobalOverview failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<RepPerformanceStat>>> fetchRepPerformance(DateTime start, DateTime end) async {
    try {
      logger.d('StatsRepository → fetchRepPerformance: $start to $end');
      final result = await _supabase.rpc('get_rep_performance_stats', params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      });
      if (result == null) return const AppSuccess([]);
      return AppSuccess(
        (result as List).map((e) => RepPerformanceStat.fromMap(e as Map<String, dynamic>)).toList(),
      );
    } catch (e, st) {
      logger.e('StatsRepository → fetchRepPerformance failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<MonthlyOrderStat>>> fetchMonthlySummary(DateTime start, DateTime end) async {
    try {
      logger.d('StatsRepository → fetchMonthlySummary: $start to $end');
      final result = await _supabase.rpc('get_orders_monthly_summary', params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      });
      if (result == null) return const AppSuccess([]);
      return AppSuccess(
        (result as List).map((e) => MonthlyOrderStat.fromMap(e as Map<String, dynamic>)).toList(),
      );
    } catch (e, st) {
      logger.e('StatsRepository → fetchMonthlySummary failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<EntityFrequencyStat>>> fetchEntityFrequency(
    DateTime start,
    DateTime end, {
    int limit = 10,
  }) async {
    try {
      logger.d('StatsRepository → fetchEntityFrequency: $start to $end, limit: $limit');
      final result = await _supabase.rpc('get_entity_frequency', params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
        'p_limit': limit,
      });
      if (result == null) return const AppSuccess([]);
      return AppSuccess(
        (result as List).map((e) => EntityFrequencyStat.fromMap(e as Map<String, dynamic>)).toList(),
      );
    } catch (e, st) {
      logger.e('StatsRepository → fetchEntityFrequency failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<StatsData>> fetchAll(DateTime start, DateTime end) async {
    try {
      logger.d('StatsRepository → fetchAll: $start to $end');
      final results = await Future.wait([
        fetchGlobalOverview(start, end),
        fetchRepPerformance(start, end),
        fetchMonthlySummary(start, end),
        fetchEntityFrequency(start, end),
      ]);
      // Propagate the first failure encountered
      for (final r in results) {
        if (r is AppFailure) return AppFailure((r as AppFailure).error);
      }
      return AppSuccess(StatsData(
        globalOverview: (results[0] as AppSuccess<GlobalStatsSummary>).data,
        repPerformance: (results[1] as AppSuccess<List<RepPerformanceStat>>).data,
        monthlySummary: (results[2] as AppSuccess<List<MonthlyOrderStat>>).data,
        entityFrequency: (results[3] as AppSuccess<List<EntityFrequencyStat>>).data,
      ));
    } catch (e, st) {
      logger.e('StatsRepository → fetchAll failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
