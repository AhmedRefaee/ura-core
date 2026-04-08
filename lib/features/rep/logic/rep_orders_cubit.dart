import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  RepOrdersCubit(this._repo) : super(RepOrdersInitial());

  Future<void> loadOrders() async {
    logger.d('RepOrdersCubit → loadOrders');
    emit(RepOrdersLoading());
    try {
      final orders = await _repo.fetchMyOrders();
      emit(RepOrdersLoaded(orders));
    } catch (e, st) {
      logger.e('RepOrdersCubit → loadOrders failed', error: e, stackTrace: st);
      emit(RepOrdersError(e.toString()));
    }
  }
}
