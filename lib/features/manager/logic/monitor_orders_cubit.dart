import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../data/manager_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ── States ────────────────────────────────────────────────────────────────────

abstract class MonitorOrdersState extends Equatable {
  const MonitorOrdersState();
  @override
  List<Object?> get props => [];
}

class MonitorOrdersInitial extends MonitorOrdersState {}

class MonitorOrdersLoading extends MonitorOrdersState {}

class MonitorOrdersLoaded extends MonitorOrdersState {
  final List<Order> activeOrders;
  final List<Order> finishedOrders;
  final bool hasMoreFinished;
  final bool isLoadingMoreFinished;

  const MonitorOrdersLoaded({
    required this.activeOrders,
    required this.finishedOrders,
    this.hasMoreFinished = true,
    this.isLoadingMoreFinished = false,
  });

  MonitorOrdersLoaded copyWith({
    List<Order>? activeOrders,
    List<Order>? finishedOrders,
    bool? hasMoreFinished,
    bool? isLoadingMoreFinished,
  }) {
    return MonitorOrdersLoaded(
      activeOrders: activeOrders ?? this.activeOrders,
      finishedOrders: finishedOrders ?? this.finishedOrders,
      hasMoreFinished: hasMoreFinished ?? this.hasMoreFinished,
      isLoadingMoreFinished:
          isLoadingMoreFinished ?? this.isLoadingMoreFinished,
    );
  }

  @override
  List<Object?> get props => [
    activeOrders,
    finishedOrders,
    hasMoreFinished,
    isLoadingMoreFinished,
  ];
}

class MonitorOrdersError extends MonitorOrdersState {
  final String message;
  const MonitorOrdersError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class MonitorOrdersCubit extends Cubit<MonitorOrdersState>
    with SafeEmit<MonitorOrdersState> {
  final ManagerRepository _repo;
  RealtimeChannel? _channel;
  int _finishedPage = 0;
  static const int _pageSize = 30;

  MonitorOrdersCubit(this._repo) : super(MonitorOrdersInitial());

  Future<void> load() async {
    logger.d('MonitorOrdersCubit → load');
    safeEmit(MonitorOrdersLoading());
    _finishedPage = 0;
    await _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final activeResult = await _repo.fetchActiveOrders();
    final activeError = activeResult.failureOrNull;
    if (activeError != null) {
      logger.e('MonitorOrdersCubit → load failed: ${activeError.message}');
      if (!isClosed) safeEmit(MonitorOrdersError(activeError.message));
      return;
    }

    final finishedResult = await _repo.fetchFinishedOrders(
      page: 0,
      pageSize: _pageSize,
    );
    final finishedError = finishedResult.failureOrNull;
    if (finishedError != null) {
      logger.e('MonitorOrdersCubit → load failed: ${finishedError.message}');
      if (!isClosed) safeEmit(MonitorOrdersError(finishedError.message));
      return;
    }

    final active = (activeResult as AppSuccess<List<Order>>).data;
    final finished = (finishedResult as AppSuccess<List<Order>>).data;
    _finishedPage = 1;

    if (!isClosed) {
      safeEmit(
        MonitorOrdersLoaded(
          activeOrders: active,
          finishedOrders: finished,
          hasMoreFinished: finished.length == _pageSize,
        ),
      );
    }

    _channel ??= Supabase.instance.client
        .channel('monitor-orders-$hashCode')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _onRealtimeEvent(),
        )
        .subscribe();
  }

  Future<void> _onRealtimeEvent() async {
    final activeResult = await _repo.fetchActiveOrders();
    if (isClosed || activeResult is! AppSuccess<List<Order>>) return;
    final current = state;
    if (current is! MonitorOrdersLoaded) return;
    safeEmit(current.copyWith(activeOrders: activeResult.data));
  }

  Future<void> loadMoreFinished() async {
    final current = state;
    if (current is! MonitorOrdersLoaded) return;
    if (!current.hasMoreFinished || current.isLoadingMoreFinished) return;

    safeEmit(current.copyWith(isLoadingMoreFinished: true));
    final result = await _repo.fetchFinishedOrders(
      page: _finishedPage,
      pageSize: _pageSize,
    );
    if (isClosed) return;

    switch (result) {
      case AppSuccess(:final data):
        _finishedPage++;
        safeEmit(
          current.copyWith(
            finishedOrders: [...current.finishedOrders, ...data],
            hasMoreFinished: data.length == _pageSize,
            isLoadingMoreFinished: false,
          ),
        );
      case AppFailure(:final error):
        logger.e(
          'MonitorOrdersCubit → loadMoreFinished failed: ${error.message}',
        );
        safeEmit(current.copyWith(isLoadingMoreFinished: false));
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
