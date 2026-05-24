import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  StreamSubscription? _authStateSub;
  AppLifecycleState? _lastLifecycleState;

  OrderChatBadgeCubit(this._repo) : super(const OrderChatBadgeState({})) {
    _logDiagnostic('Cubit initialized');
    _monitorAuthState();
    _monitorAppLifecycle();
  }

  void _logDiagnostic(String message) {
    final authState = Supabase.instance.client.auth.currentSession;
    final lifecycleState = _lastLifecycleState?.name ?? 'unknown';
    final subActive = _sub != null ? 'active' : 'inactive';
    
    logger.i('OrderChatBadgeCubit DIAGNOSTIC: $message | '
        'Auth: ${authState != null ? "authenticated" : "unauthenticated"} | '
        'Lifecycle: $lifecycleState | '
        'Subscription: $subActive');
  }

  void _monitorAuthState() {
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        _logDiagnostic('Auth state changed: ${data.event}');
        if (data.event == AuthChangeEvent.signedOut) {
          logger.w('OrderChatBadgeCubit → User signed out, cancelling subscription');
          _sub?.cancel();
          _sub = null;
          emit(const OrderChatBadgeState({}));
        } else if (data.event == AuthChangeEvent.tokenRefreshed) {
          logger.d('OrderChatBadgeCubit → Token refreshed');
          if (_sub == null) {
            logger.w('OrderChatBadgeCubit → Subscription was gone after token refresh, resubscribing');
            subscribe();
          }
        }
      },
      onError: (e, st) {
        logger.e('OrderChatBadgeCubit → Auth state error', error: e, stackTrace: st);
      },
    );
  }

  void _monitorAppLifecycle() {
    WidgetsBinding.instance.addObserver(_LifecycleObserver(this));
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    _lastLifecycleState = state;
    _logDiagnostic('App lifecycle changed to: ${state.name}');
    
    if (state == AppLifecycleState.resumed) {
      logger.d('OrderChatBadgeCubit → App resumed, checking subscription health');
      if (_sub == null) {
        logger.w('OrderChatBadgeCubit → No active subscription after resume, will resubscribe');
        subscribe();
      } else {
        logger.d('OrderChatBadgeCubit → Subscription still active after resume');
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      logger.d('OrderChatBadgeCubit → App paused/inactive, connection may be closed by OS');
    }
  }

  void subscribe() {
    if (_sub != null) {
      logger.w('OrderChatBadgeCubit → Subscribe called but subscription already exists');
      return;
    }
    
    _logDiagnostic('Attempting to subscribe to urgent counts');
    logger.d('OrderChatBadgeCubit → subscribe');
    
    try {
      _sub = _repo.subscribeToUrgentCountsByOrder().listen(
        (counts) {
          logger.d('OrderChatBadgeCubit → ${counts.length} orders with urgent messages');
          _logDiagnostic('Successfully received counts update');
          emit(OrderChatBadgeState(counts));
        },
        onError: (Object e, StackTrace st) {
          _logDiagnostic('Stream error occurred');
          logger.e('OrderChatBadgeCubit → stream error', error: e, stackTrace: st);
          
          // Log additional error details
          if (e.toString().contains('channelError')) {
            logger.e('OrderChatBadgeCubit → Channel error detected - connection likely closed');
          }
          if (e.toString().contains('RealtimeSubscribeException')) {
            logger.e('OrderChatBadgeCubit → Realtime subscription failed');
          }
          
          // Cancel and clear so it can be recreated on next token refresh
          _sub?.cancel();
          _sub = null;
          _logDiagnostic('Subscription cleared after error');
        },
        onDone: () {
          logger.w('OrderChatBadgeCubit → Stream completed unexpectedly');
          _sub?.cancel();
          _sub = null;
          _logDiagnostic('Stream done, subscription cleared');
        },
        cancelOnError: false,
      );
      
      _logDiagnostic('Subscription listener attached successfully');
    } catch (e, st) {
      logger.e('OrderChatBadgeCubit → Exception during subscribe', error: e, stackTrace: st);
      _sub = null;
    }
  }

  @override
  Future<void> close() {
    logger.d('OrderChatBadgeCubit → close');
    _logDiagnostic('Cubit closing, cleaning up resources');
    _sub?.cancel();
    _authStateSub?.cancel();
    WidgetsBinding.instance.removeObserver(_LifecycleObserver(this));
    return super.close();
  }
}

// ─── Lifecycle Observer ──────────────────────────────────────────────────────

class _LifecycleObserver with WidgetsBindingObserver {
  final OrderChatBadgeCubit _cubit;
  
  _LifecycleObserver(this._cubit);
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _cubit.onAppLifecycleChanged(state);
  }
}
