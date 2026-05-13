import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../data/rep_orders_repository.dart';

abstract class RepOrdersState extends Equatable {
  const RepOrdersState();
  @override
  List<Object?> get props => [];
}

class RepOrdersInitial extends RepOrdersState {}

class RepOrdersLoading extends RepOrdersState {}

class RepOrdersLoaded extends RepOrdersState {
  final List<Order> orders;
  const RepOrdersLoaded(this.orders);
  @override
  List<Object?> get props => [orders];
}

class RepOrdersError extends RepOrdersState {
  final String message;
  const RepOrdersError(this.message);
  @override
  List<Object?> get props => [message];
}

class RepOrdersCubit extends Cubit<RepOrdersState> {
  final RepOrdersRepository _repo;
  RealtimeChannel? _channel;

  RepOrdersCubit(this._repo) : super(RepOrdersInitial());

  Future<void> loadOrders() async {
    logger.d('RepOrdersCubit → loadOrders');
    emit(RepOrdersLoading());
    await _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final result = await _repo.fetchMyOrders();
    switch (result) {
      case AppSuccess(:final data):
        emit(RepOrdersLoaded(data));
        _channel ??= Supabase.instance.client
            .channel('rep-orders-$hashCode')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'orders',
              callback: (_) => _fetchOrders(),
            )
            .subscribe();
      case AppFailure(:final error):
        logger.e('RepOrdersCubit → loadOrders failed: ${error.message}');
        emit(RepOrdersError(error.message));
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
