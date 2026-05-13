import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/notifications/notification_dispatcher.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_edit_log_entry.dart';
import '../../../shared/models/profile.dart';

class OrderRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, '
      'entity:entities(*), '
      'rep:profiles!orders_rep_id_fkey(id, full_name, role, is_approved, phone, created_at), '
      'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), '
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

  Future<AppResult<List<Order>>> fetchAllOrders() async {
    try {
      logger.d('OrderRepository → fetchAllOrders');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .order('created_at', ascending: false);
      final orders = (data as List)
          .map((e) => Order.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('OrderRepository → loaded ${orders.length} orders');
      return AppSuccess(orders);
    } catch (e, st) {
      logger.e('OrderRepository → fetchAllOrders failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Profile>>> fetchReps() async {
    try {
      logger.d('OrderRepository → fetchReps');
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved, created_at')
          .eq('role', 'rep')
          .eq('is_approved', true)
          .order('full_name');
      final reps = (data as List)
          .map((e) => Profile.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('OrderRepository → loaded ${reps.length} reps');
      return AppSuccess(reps);
    } catch (e, st) {
      logger.e('OrderRepository → fetchReps failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Profile>>> fetchPendingUsers() async {
    try {
      logger.d('OrderRepository → fetchPendingUsers');
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved, created_at')
          .eq('is_approved', false)
          .order('created_at');
      final users = (data as List)
          .map((e) => Profile.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('OrderRepository → ${users.length} pending users');
      return AppSuccess(users);
    } catch (e, st) {
      logger.e('OrderRepository → fetchPendingUsers failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> approveUser(String userId, String role) async {
    try {
      logger.d('OrderRepository → approveUser: $userId | role: $role');
      final result = await _supabase.rpc('approve_user', params: {
        'target_user_id': userId,
        'assigned_role': role,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('OrderRepository → approveUser success: $userId as $role');
        NotificationDispatcher.send(
          userIds: [userId],
          title: 'تمت الموافقة على حسابك',
          body: 'مرحباً بك في URA! يمكنك الآن تسجيل الدخول.',
          route: '/$role',
        ).ignore();
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('OrderRepository → approveUser failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<String>> createOrder({
    required String direction,
    required String entityId,
    String? repId,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      logger.d('OrderRepository → createOrder | direction: $direction | entity: $entityId');
      final orderData = await _supabase
          .from('orders')
          .insert({
            'direction': direction,
            'entity_id': entityId,
            'rep_id': ?repId,
            'status': 'assigned',
            'notes': notes?.isNotEmpty == true ? notes : null,
            'created_by': _supabase.auth.currentUser!.id,
            'assigned_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();

      final orderId = orderData['id'] as String;
      logger.d('OrderRepository → order created: $orderId, inserting ${items.length} items');

      final itemRows = items.map((item) => {'order_id': orderId, ...item}).toList();
      await _supabase.from('order_items').insert(itemRows);
      logger.i('OrderRepository → createOrder complete: $orderId');
      return AppSuccess(orderId);
    } catch (e, st) {
      logger.e('OrderRepository → createOrder failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Order>> fetchOrderForEdit(String orderId) async {
    try {
      logger.d('OrderRepository → fetchOrderForEdit: $orderId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('id', orderId)
          .single();
      final order = Order.fromMap(data);
      logger.i('OrderRepository → fetchOrderForEdit loaded: ${order.items.length} items');
      return AppSuccess(order);
    } catch (e, st) {
      logger.e('OrderRepository → fetchOrderForEdit failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> editOrderItems({
    required String orderId,
    required String reason,
    List<Map<String, dynamic>> updates = const [],
    List<String> removals = const [],
    List<Map<String, dynamic>> additions = const [],
  }) async {
    try {
      logger.d('OrderRepository → editOrderItems: $orderId | reason: $reason');
      final result = await _supabase.rpc('edit_order_items', params: {
        'p_order_id': orderId,
        'p_reason': reason,
        'p_updates': updates,
        'p_removals': removals,
        'p_additions': additions,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('OrderRepository → editOrderItems success: ${result['changes_count']} changes');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('OrderRepository → editOrderItems failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<OrderEditLogEntry>>> fetchEditLog(String orderId) async {
    try {
      logger.d('OrderRepository → fetchEditLog: $orderId');
      final data = await _supabase
          .from('order_edit_log')
          .select('id, order_id, performed_by, reason, changes, server_timestamp, performer:profiles!order_edit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)')
          .eq('order_id', orderId)
          .order('server_timestamp', ascending: false);
      final entries = (data as List)
          .map((e) => OrderEditLogEntry.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('OrderRepository → fetchEditLog loaded: ${entries.length} entries');
      return AppSuccess(entries);
    } catch (e, st) {
      logger.e('OrderRepository → fetchEditLog failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Map<String, String>>> fetchReceipts(String orderId) async {
    try {
      logger.d('OrderRepository → fetchReceipts: $orderId');
      final data = await _supabase
          .from('receipts')
          .select('order_item_id, image_url')
          .eq('order_id', orderId);
      final map = <String, String>{};
      for (final row in data as List) {
        map[row['order_item_id'] as String] = row['image_url'] as String;
      }
      logger.i('OrderRepository → ${map.length} receipts for order $orderId');
      return AppSuccess(map);
    } catch (e, st) {
      logger.e('OrderRepository → fetchReceipts failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
