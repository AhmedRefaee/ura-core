import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../data/storage_repository.dart';

abstract class StorageOrdersState extends Equatable {
  const StorageOrdersState();
  @override
  List<Object?> get props => [];
}

class StorageOrdersInitial extends StorageOrdersState {}

class StorageOrdersLoading extends StorageOrdersState {}

class StorageOrdersLoaded extends StorageOrdersState {
  final List<Order> orders;
  const StorageOrdersLoaded(this.orders);
  @override
  List<Object?> get props => [orders];
}

class StorageOrdersError extends StorageOrdersState {
  final String message;
  const StorageOrdersError(this.message);
  @override
  List<Object?> get props => [message];
}

class StorageOrdersCubit extends Cubit<StorageOrdersState> {
  final StorageRepository _repo;

  StorageOrdersCubit(this._repo) : super(StorageOrdersInitial());

  Future<void> loadOrders() async {
    logger.d('StorageOrdersCubit → loadOrders');
    emit(StorageOrdersLoading());
    try {
      final orders = await _repo.fetchAssignedOrders();
      emit(StorageOrdersLoaded(orders));
    } catch (e, st) {
      logger.e('StorageOrdersCubit → load failed', error: e, stackTrace: st);
      emit(StorageOrdersError(e.toString()));
    }
  }
}
