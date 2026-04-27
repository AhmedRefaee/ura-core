import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  /// Orders where the storage actor still needs to act (shared queue).
  final List<Order> activeOrders;

  /// Orders this specific storage actor has already completed.
  final List<Order> doneOrders;

  const StorageOrdersLoaded({
    this.activeOrders = const [],
    this.doneOrders = const [],
  });

  @override
  List<Object?> get props => [activeOrders, doneOrders];
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
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final results = await Future.wait([
        _repo.fetchActiveForStorage(),
        _repo.fetchDoneByStorageActor(userId),
      ]);
      emit(StorageOrdersLoaded(
        activeOrders: results[0],
        doneOrders: results[1],
      ));
    } catch (e, st) {
      logger.e('StorageOrdersCubit → load failed', error: e, stackTrace: st);
      emit(StorageOrdersError(e.toString()));
    }
  }
}
