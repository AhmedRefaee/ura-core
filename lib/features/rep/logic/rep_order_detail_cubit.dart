import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/order.dart';
import '../data/rep_orders_repository.dart';
import '../../chat/data/chat_repository.dart';

import '../../../core/logic/safe_emit.dart';

abstract class RepOrderDetailState extends Equatable {
  const RepOrderDetailState();
  @override
  List<Object?> get props => [];
}

class RepOrderDetailInitial extends RepOrderDetailState {}

class RepOrderDetailLoading extends RepOrderDetailState {}

class RepOrderDetailLoaded extends RepOrderDetailState {
  final Order order;
  final List<AuditLogEntry> auditLog;
  final bool isActing;
  final List<ChatMessage> communicationHistory;

  const RepOrderDetailLoaded({
    required this.order,
    this.auditLog = const [],
    this.isActing = false,
    this.communicationHistory = const [],
  });

  RepOrderDetailLoaded copyWith({
    Order? order,
    List<AuditLogEntry>? auditLog,
    bool? isActing,
    List<ChatMessage>? communicationHistory,
  }) {
    return RepOrderDetailLoaded(
      order: order ?? this.order,
      auditLog: auditLog ?? this.auditLog,
      isActing: isActing ?? this.isActing,
      communicationHistory: communicationHistory ?? this.communicationHistory,
    );
  }

  @override
  List<Object?> get props => [order, auditLog, isActing, communicationHistory];
}

class RepOrderDetailError extends RepOrderDetailState {
  final String message;
  const RepOrderDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class RepOrderDetailCubit extends Cubit<RepOrderDetailState>
    with SafeEmit<RepOrderDetailState> {
  final RepOrdersRepository _repo;
  final ChatRepository _chatRepo;
  final String orderId;

  RepOrderDetailCubit(this._repo, this.orderId, this._chatRepo)
    : super(RepOrderDetailInitial());

  Future<void> load() async {
    logger.d('RepOrderDetailCubit → load: $orderId');
    safeEmit(RepOrderDetailLoading());

    final results = await Future.wait([
      _repo.fetchOrderDetail(orderId),
      _repo.fetchAuditLog(orderId),
      _chatRepo.getOrderCommunicationHistory(orderId),
    ]);

    if (isClosed) return;

    final orderError = results[0].failureOrNull;
    if (orderError != null) {
      logger.e('RepOrderDetailCubit → load failed: ${orderError.message}');
      safeEmit(RepOrderDetailError(orderError.message));
      return;
    }
    // Audit log failure is non-fatal — show empty timeline rather than error screen
    final auditLog = results[1] is AppSuccess<List<AuditLogEntry>>
        ? (results[1] as AppSuccess<List<AuditLogEntry>>).data
        : <AuditLogEntry>[];
    final historyError = results[2].failureOrNull;
    if (historyError != null) {
      logger.e('RepOrderDetailCubit → load failed: ${historyError.message}');
      safeEmit(RepOrderDetailError(historyError.message));
      return;
    }

    final order = (results[0] as AppSuccess<Order>).data;

    safeEmit(
      RepOrderDetailLoaded(
        order: order,
        auditLog: auditLog,
        communicationHistory:
            (results[2] as AppSuccess<List<ChatMessage>>).data,
      ),
    );
  }

  Future<void> startMove({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → startMove');
    safeEmit(s.copyWith(isActing: true));
    final result = await _repo.startMove(orderId, notes: notes);
    switch (result) {
      case AppSuccess():
        await load();
      case AppFailure(:final error):
        logger.e('RepOrderDetailCubit → startMove failed: ${error.message}');
        safeEmit(RepOrderDetailError(error.message));
    }
  }

  Future<void> markPickedUp({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → markPickedUp');
    safeEmit(s.copyWith(isActing: true));
    final result = await _repo.markPickedUp(orderId, notes: notes);
    switch (result) {
      case AppSuccess():
        await load();
      case AppFailure(:final error):
        logger.e('RepOrderDetailCubit → markPickedUp failed: ${error.message}');
        safeEmit(RepOrderDetailError(error.message));
    }
  }

  Future<void> markDelivered({String? notes}) async {
    final s = state;
    if (s is! RepOrderDetailLoaded) return;
    logger.d('RepOrderDetailCubit → markDelivered');
    safeEmit(s.copyWith(isActing: true));
    final result = await _repo.markDelivered(orderId, notes: notes);
    switch (result) {
      case AppSuccess():
        await load();
      case AppFailure(:final error):
        logger.e(
          'RepOrderDetailCubit → markDelivered failed: ${error.message}',
        );
        safeEmit(RepOrderDetailError(error.message));
    }
  }
}
