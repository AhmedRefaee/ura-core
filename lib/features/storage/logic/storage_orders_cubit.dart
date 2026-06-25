import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../data/storage_repository.dart';

import '../../../core/logic/safe_emit.dart';

abstract class StorageOrdersState extends Equatable {
  const StorageOrdersState();
  @override
  List<Object?> get props => [];
}

class StorageOrdersInitial extends StorageOrdersState {}

class StorageOrdersLoading extends StorageOrdersState {}

class StorageOrdersLoaded extends StorageOrdersState {
  final List<Order> activeOrders;
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

class StorageOrdersCubit extends Cubit<StorageOrdersState>
    with SafeEmit<StorageOrdersState> {
  final StorageRepository _repo;
  RealtimeChannel? _channel;

  StorageOrdersCubit(this._repo) : super(StorageOrdersInitial());

  Future<void> loadOrders() async {
    logger.d('StorageOrdersCubit → loadOrders');
    safeEmit(StorageOrdersLoading());
    await _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;

    final results = await Future.wait([
      _repo.fetchActiveForStorage(),
      _repo.fetchDoneByStorageActor(userId),
    ]);

    final activeError = results[0].failureOrNull;
    if (activeError != null) {
      logger.e('StorageOrdersCubit → load failed: ${activeError.message}');
      safeEmit(StorageOrdersError(activeError.message));
      return;
    }
    final doneError = results[1].failureOrNull;
    if (doneError != null) {
      logger.e('StorageOrdersCubit → load failed: ${doneError.message}');
      safeEmit(StorageOrdersError(doneError.message));
      return;
    }

    safeEmit(
      StorageOrdersLoaded(
        activeOrders: (results[0] as AppSuccess<List<Order>>).data,
        doneOrders: (results[1] as AppSuccess<List<Order>>).data,
      ),
    );
    _channel ??= Supabase.instance.client
        .channel('storage-orders-$hashCode')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _fetchOrders(),
        )
        .subscribe();
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }
}
