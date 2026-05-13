import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../data/order_repository.dart';
import 'orders_state.dart';

class OrdersCubit extends Cubit<OrdersState> {
  final OrderRepository _repo;
  RealtimeChannel? _channel;

  OrdersCubit(this._repo) : super(OrdersInitial());

  Future<void> loadOrders() async {
    logger.d('OrdersCubit → loadOrders');
    emit(OrdersLoading());
    await _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final result = await _repo.fetchAllOrders();
    switch (result) {
      case AppSuccess(:final data):
        emit(OrdersLoaded(data));
        _channel ??= Supabase.instance.client
            .channel('orders-cubit-$hashCode')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'orders',
              callback: (_) => _fetchOrders(),
            )
            .subscribe();
      case AppFailure(:final error):
        logger.e('OrdersCubit → loadOrders failed: ${error.message}');
        emit(OrdersError(error.message));
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
