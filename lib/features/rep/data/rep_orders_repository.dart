import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';

class RepOrdersRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, '
      'entity:entities(*), '
      'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), '
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

  Future<AppResult<List<Order>>> fetchMyOrders() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      logger.d('RepOrdersRepository → fetchMyOrders for $userId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('rep_id', userId)
          .order('created_at', ascending: false);
      final orders = (data as List)
          .map((e) => Order.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('RepOrdersRepository → ${orders.length} orders loaded');
      return AppSuccess(orders);
    } catch (e, st) {
      logger.e('RepOrdersRepository → fetchMyOrders failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Order>> fetchOrderDetail(String orderId) async {
    try {
      logger.d('RepOrdersRepository → fetchOrderDetail: $orderId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('id', orderId)
          .single();
      return AppSuccess(Order.fromMap(data));
    } catch (e, st) {
      logger.e('RepOrdersRepository → fetchOrderDetail failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> startMove(String orderId, {String? notes}) async {
    try {
      logger.d('RepOrdersRepository → startMove: $orderId');
      final result = await _supabase.rpc('start_move', params: {
        'target_order_id': orderId,
        'p_notes': notes,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('RepOrdersRepository → startMove success: $orderId');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('RepOrdersRepository → startMove failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> markPickedUp(String orderId, {String? notes}) async {
    try {
      logger.d('RepOrdersRepository → markPickedUp: $orderId');
      final result = await _supabase.rpc('mark_picked_up', params: {
        'target_order_id': orderId,
        'p_notes': notes,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('RepOrdersRepository → markPickedUp success: $orderId');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('RepOrdersRepository → markPickedUp failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> markDelivered(String orderId, {String? notes}) async {
    try {
      logger.d('RepOrdersRepository → markDelivered: $orderId');
      final result = await _supabase.rpc('mark_delivered', params: {
        'target_order_id': orderId,
        'p_notes': notes,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('RepOrdersRepository → markDelivered success: $orderId');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('RepOrdersRepository → markDelivered failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<AuditLogEntry>>> fetchAuditLog(String orderId) async {
    try {
      logger.d('RepOrdersRepository → fetchAuditLog: $orderId');
      final data = await _supabase
          .from('audit_log')
          .select(
              'id, order_id, action, old_status, new_status, performed_by, details, notes, server_timestamp, '
              'performer:profiles!audit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)')
          .eq('order_id', orderId)
          .order('server_timestamp');
      return AppSuccess((data as List)
          .map((e) => AuditLogEntry.fromMap(e as Map<String, dynamic>))
          .toList());
    } catch (e, st) {
      logger.e('RepOrdersRepository → fetchAuditLog failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

}
