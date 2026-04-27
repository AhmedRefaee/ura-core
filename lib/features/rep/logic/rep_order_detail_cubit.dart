import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/order.dart';
import '../data/rep_orders_repository.dart';
import '../../chat/data/chat_repository.dart';

abstract class RepOrderDetailState extends Equatable {
  const RepOrderDetailState();
  @override
  List<Object?> get props => [];
}

class RepOrderDetailInitial extends RepOrderDetailState {}

class RepOrderDetailLoading extends RepOrderDetailState {}

class RepOrderDetailLoaded extends RepOrderDetailState {
  final Order order;
  final Map<String, String> receipts; // orderItemId → imageUrl
  final bool isActing;
  final List<ChatMessage> communicationHistory;

  const RepOrderDetailLoaded({
    required this.order,
    required this.receipts,
    this.isActing = false,
    this.communicationHistory = const [],
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
  }) {
    return RepOrderDetailLoaded(
      order: order ?? this.order,
      receipts: receipts ?? this.receipts,
      isActing: isActing ?? this.isActing,
      communicationHistory: communicationHistory ?? this.communicationHistory,
    );
  }

  @override
  List<Object?> get props => [order, receipts, isActing, communicationHistory];
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
  final String orderId;

  RepOrderDetailCubit(this._repo, this.orderId, this._chatRepo)
      : super(RepOrderDetailInitial());

  Future<void> load() async {
    logger.d('RepOrderDetailCubit → load: $orderId');
    emit(RepOrderDetailLoading());
    try {
      final results = await Future.wait([
        _repo.fetchOrderDetail(orderId),
        _repo.fetchReceipts(orderId),
        _chatRepo.getOrderCommunicationHistory(orderId),
      ]);

      emit(RepOrderDetailLoaded(
        order: results[0] as Order,
        receipts: results[1] as Map<String, String>,
        communicationHistory: results[2] as List<ChatMessage>,
      ));
    } catch (e, st) {
      logger.e('RepOrderDetailCubit → load failed', error: e, stackTrace: st);
      emit(RepOrderDetailError(e.toString()));
    }
  }

  Future<void> startMove({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → startMove');
    emit(s.copyWith(isActing: true));
    try {
      await _repo.startMove(orderId, notes: notes);
      await load();
    } catch (e, st) {
      logger.e('RepOrderDetailCubit → startMove failed', error: e, stackTrace: st);
      emit(RepOrderDetailError(e.toString()));
    }
  }

  Future<void> markPickedUp({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → markPickedUp');
    emit(s.copyWith(isActing: true));
    try {
      await _repo.markPickedUp(orderId, notes: notes);
      await load();
    } catch (e, st) {
      logger.e('RepOrderDetailCubit → markPickedUp failed', error: e, stackTrace: st);
      emit(RepOrderDetailError(e.toString()));
    }
  }

  Future<void> markDelivered({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → markDelivered');
    emit(s.copyWith(isActing: true));
    try {
      await _repo.markDelivered(orderId, notes: notes);
      await load();
    } catch (e, st) {
      logger.e('RepOrderDetailCubit → markDelivered failed', error: e, stackTrace: st);
      emit(RepOrderDetailError(e.toString()));
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
    try {
      final url = await _repo.uploadReceipt(
        orderId: orderId,
        orderItemId: orderItemId,
        imageFile: imageFile,
      );
      final updatedReceipts = Map<String, String>.from(s.receipts)
        ..[orderItemId] = url;
      final order = await _repo.fetchOrderDetail(orderId);
      emit(RepOrderDetailLoaded(
        order: order,
        receipts: updatedReceipts,
        communicationHistory: s.communicationHistory,
      ));
    } catch (e, st) {
      logger.e('RepOrderDetailCubit → uploadReceipt failed', error: e, stackTrace: st);
      emit(RepOrderDetailError(e.toString()));
    }
  }
}
