import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../data/order_repository.dart';
import 'orders_state.dart';

class OrdersCubit extends Cubit<OrdersState> {
  final OrderRepository _repo;

  OrdersCubit(this._repo) : super(OrdersInitial());

  Future<void> loadOrders() async {
    logger.d('OrdersCubit → loadOrders');
    emit(OrdersLoading());
    try {
      final orders = await _repo.fetchAllOrders();
      emit(OrdersLoaded(orders));
    } catch (e, st) {
      logger.e('OrdersCubit → loadOrders failed', error: e, stackTrace: st);
      emit(OrdersError(e.toString()));
    }
  }
}
