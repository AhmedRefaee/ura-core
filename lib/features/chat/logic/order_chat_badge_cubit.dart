import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../data/chat_repository.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class OrderChatBadgeState extends Equatable {
  final Map<String, int> urgentCountByOrderId;
  const OrderChatBadgeState(this.urgentCountByOrderId);

  bool hasUrgent(String orderId) => urgentCountByOrderId.containsKey(orderId);
  int getCount(String orderId) => urgentCountByOrderId[orderId] ?? 0;

  @override
  List<Object?> get props => [urgentCountByOrderId];
}

// ─── Cubit ───────────────────────────────────────────────────────────────────

class OrderChatBadgeCubit extends Cubit<OrderChatBadgeState> {
  final ChatRepository _repo;
  StreamSubscription<Map<String, int>>? _sub;

  OrderChatBadgeCubit(this._repo) : super(const OrderChatBadgeState({}));

  void subscribe() {
    if (_sub != null) return; // already subscribed
    logger.d('OrderChatBadgeCubit → subscribe');
    _sub = _repo.subscribeToUrgentCountsByOrder().listen(
      (counts) {
        logger.d('OrderChatBadgeCubit → ${counts.length} orders with urgent messages');
        emit(OrderChatBadgeState(counts));
      },
      onError: (Object e, StackTrace st) {
        logger.e('OrderChatBadgeCubit → stream error', error: e, stackTrace: st);
      },
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
