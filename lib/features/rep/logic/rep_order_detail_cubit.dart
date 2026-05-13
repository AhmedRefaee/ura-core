import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/order.dart';
import '../data/rep_orders_repository.dart';
import '../../chat/data/chat_repository.dart';
import '../../verifier/data/inventory_repository.dart';

abstract class RepOrderDetailState extends Equatable {
  const RepOrderDetailState();
  @override
  List<Object?> get props => [];
}

class RepOrderDetailInitial extends RepOrderDetailState {}

class RepOrderDetailLoading extends RepOrderDetailState {}

class RepOrderDetailLoaded extends RepOrderDetailState {
  final Order order;
  final Map<String, String> receipts;
  final bool isActing;
  final List<ChatMessage> communicationHistory;
  final Map<String, InventoryItem> stockItems;

  const RepOrderDetailLoaded({
    required this.order,
    required this.receipts,
    this.isActing = false,
    this.communicationHistory = const [],
    this.stockItems = const {},
  });

  bool get allCustomItemsHaveReceipts {
    final customItems = order.items.where((i) => i.isCustom).toList();
    if (customItems.isEmpty) return true;
    return customItems.every((i) => receipts.containsKey(i.id));
  }

  RepOrderDetailLoaded copyWith({
    Order? order,
    Map<String, String>? receipts,
    bool? isActing,
    List<ChatMessage>? communicationHistory,
    Map<String, InventoryItem>? stockItems,
  }) {
    return RepOrderDetailLoaded(
      order: order ?? this.order,
      receipts: receipts ?? this.receipts,
      isActing: isActing ?? this.isActing,
      communicationHistory: communicationHistory ?? this.communicationHistory,
      stockItems: stockItems ?? this.stockItems,
    );
  }

  @override
  List<Object?> get props => [order, receipts, isActing, communicationHistory, stockItems];
}

class RepOrderDetailError extends RepOrderDetailState {
  final String message;
  const RepOrderDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class RepOrderDetailCubit extends Cubit<RepOrderDetailState> {
  final RepOrdersRepository _repo;
  final ChatRepository _chatRepo;
  final InventoryRepository _inventoryRepo;
  final String orderId;

  RepOrderDetailCubit(this._repo, this.orderId, this._chatRepo, this._inventoryRepo)
      : super(RepOrderDetailInitial());

  Future<void> load() async {
    logger.d('RepOrderDetailCubit → load: $orderId');
    emit(RepOrderDetailLoading());

    final results = await Future.wait([
      _repo.fetchOrderDetail(orderId),
      _repo.fetchReceipts(orderId),
      _chatRepo.getOrderCommunicationHistory(orderId),
    ]);

    final orderError = results[0].failureOrNull;
    if (orderError != null) {
      logger.e('RepOrderDetailCubit → load failed: ${orderError.message}');
      emit(RepOrderDetailError(orderError.message));
      return;
    }
    final receiptsError = results[1].failureOrNull;
    if (receiptsError != null) {
      logger.e('RepOrderDetailCubit → load failed: ${receiptsError.message}');
      emit(RepOrderDetailError(receiptsError.message));
      return;
    }
    final historyError = results[2].failureOrNull;
    if (historyError != null) {
      logger.e('RepOrderDetailCubit → load failed: ${historyError.message}');
      emit(RepOrderDetailError(historyError.message));
      return;
    }

    final order = (results[0] as AppSuccess<Order>).data;
    final invIds = order.items
        .where((i) => !i.isCustom && i.inventoryId != null)
        .map((i) => i.inventoryId!)
        .toList();
    final stockResult = await _inventoryRepo.fetchItemsByIds(invIds);
    final stockError = stockResult.failureOrNull;
    if (stockError != null) {
      logger.e('RepOrderDetailCubit → fetchItemsByIds failed: ${stockError.message}');
      emit(RepOrderDetailError(stockError.message));
      return;
    }

    emit(RepOrderDetailLoaded(
      order: order,
      receipts: (results[1] as AppSuccess<Map<String, String>>).data,
      communicationHistory: (results[2] as AppSuccess<List<ChatMessage>>).data,
      stockItems: (stockResult as AppSuccess<Map<String, InventoryItem>>).data,
    ));
  }

  Future<void> startMove({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → startMove');
    emit(s.copyWith(isActing: true));
    final result = await _repo.startMove(orderId, notes: notes);
    switch (result) {
      case AppSuccess():
        await load();
      case AppFailure(:final error):
        logger.e('RepOrderDetailCubit → startMove failed: ${error.message}');
        emit(RepOrderDetailError(error.message));
    }
  }

  Future<void> markPickedUp({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → markPickedUp');
    emit(s.copyWith(isActing: true));
    final result = await _repo.markPickedUp(orderId, notes: notes);
    switch (result) {
      case AppSuccess():
        await load();
      case AppFailure(:final error):
        logger.e('RepOrderDetailCubit → markPickedUp failed: ${error.message}');
        emit(RepOrderDetailError(error.message));
    }
  }

  Future<void> markDelivered({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → markDelivered');
    emit(s.copyWith(isActing: true));
    final result = await _repo.markDelivered(orderId, notes: notes);
    switch (result) {
      case AppSuccess():
        await load();
      case AppFailure(:final error):
        logger.e('RepOrderDetailCubit → markDelivered failed: ${error.message}');
        emit(RepOrderDetailError(error.message));
    }
  }

  Future<void> uploadReceipt({
    required String orderItemId,
    required File imageFile,
  }) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → uploadReceipt for item $orderItemId');
    emit(s.copyWith(isActing: true));

    final uploadResult = await _repo.uploadReceipt(
      orderId: orderId,
      orderItemId: orderItemId,
      imageFile: imageFile,
    );
    switch (uploadResult) {
      case AppSuccess(:final data):
        final updatedReceipts = Map<String, String>.from(s.receipts)..[orderItemId] = data;
        final orderResult = await _repo.fetchOrderDetail(orderId);
        switch (orderResult) {
          case AppSuccess(:final data):
            emit(RepOrderDetailLoaded(
              order: data,
              receipts: updatedReceipts,
              communicationHistory: s.communicationHistory,
              stockItems: s.stockItems,
            ));
          case AppFailure(:final error):
            logger.e('RepOrderDetailCubit → reload after upload failed: ${error.message}');
            emit(RepOrderDetailError(error.message));
        }
      case AppFailure(:final error):
        logger.e('RepOrderDetailCubit → uploadReceipt failed: ${error.message}');
        emit(RepOrderDetailError(error.message));
    }
  }
}
