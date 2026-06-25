import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/notifications/notification_dispatcher.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_edit_log_entry.dart';
import '../../../shared/models/profile.dart';

class OrderRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Safety cap: fetchAllOrders has no pagination, so without a bound this
  // query (and its nested joins) grows unbounded with order volume.
  static const _maxOrdersFetch = 2000;

  static const _orderSelect =
      '*, '
      'entity:entities(*), '
      'rep:profiles!orders_rep_id_fkey(id, full_name, role, is_approved, phone, created_at), '
      'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), '
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

  static const _orderDetailSelect =
      'id, reference_code, direction, entity_id, rep_id, created_by, storage_actor_id, status, notes, created_at, assigned_at, picked_up_at, move_started_at, delivered_at, entity:entities(id, name, category, contact_name, contact_phone, address), rep:profiles!orders_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), creator:profiles!orders_created_by_fkey(id, full_name, phone, role, is_approved, created_at), order_items(id, order_id, inventory_id, quantity, final_quantity, is_custom, custom_description, source_inventory_id, check_status, checked_by, checked_at, inventory:inventory!order_items_inventory_id_fkey(id, item_name), checker:profiles!order_items_checked_by_fkey(id, full_name, phone, role, is_approved, created_at))';

  Future<AppResult<List<Order>>> fetchAllOrders() async {
    try {
      logger.d('OrderRepository → fetchAllOrders');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .order('created_at', ascending: false)
          .limit(_maxOrdersFetch);
      final orders = (data as List)
          .map((e) => Order.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('OrderRepository → loaded ${orders.length} orders');
      return AppSuccess(orders);
    } catch (e, st) {
      logger.e(
        'OrderRepository → fetchAllOrders failed',
        error: e,
        stackTrace: st,
      );
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

  Future<AppResult<Map<String, OrderStatus>>>
  fetchLatestOrderStatusByRep() async {
    try {
      logger.d('OrderRepository → fetchLatestOrderStatusByRep');
      final data = await _supabase
          .from('orders')
          .select('rep_id, status, created_at')
          .not('rep_id', 'is', null)
          .order('created_at', ascending: false);

      final result = <String, OrderStatus>{};
      for (final row in data as List) {
        final repId = row['rep_id'] as String?;
        if (repId != null && !result.containsKey(repId)) {
          result[repId] = Order.statusFromString(row['status'] as String);
        }
      }

      logger.i('OrderRepository → latest status for ${result.length} reps');
      return AppSuccess(result);
    } catch (e, st) {
      logger.e(
        'OrderRepository → fetchLatestOrderStatusByRep failed',
        error: e,
        stackTrace: st,
      );
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
      logger.e(
        'OrderRepository → fetchPendingUsers failed',
        error: e,
        stackTrace: st,
      );
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> approveUser(String userId, String role) async {
    try {
      logger.d('OrderRepository → approveUser: $userId | role: $role');
      final result = await _supabase.rpc(
        'approve_user',
        params: {'target_user_id': userId, 'assigned_role': role},
      );
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
      logger.e(
        'OrderRepository → approveUser failed',
        error: e,
        stackTrace: st,
      );
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
      logger.d(
        'OrderRepository → createOrder | direction: $direction | entity: $entityId | ${items.length} items',
      );

      // Client-side guard: reject empty orders before any network call.
      if (items.isEmpty) {
        return AppFailure(
          ErrorHandler.fromRpcResult({
            'success': false,
            'error': 'يجب إضافة عنصر واحد على الأقل للطلب',
          }),
        );
      }

      // Atomic RPC: inserts order + items + sets was_unavailable_at_creation
      // in a single transaction. Either everything commits or nothing does.
      final result = await _supabase.rpc(
        'create_order_with_items',
        params: {
          'p_direction': direction,
          'p_entity_id': entityId,
          'p_rep_id': repId,
          'p_notes': notes,
          'p_items': items,
        },
      );

      if (result['success'] as bool? ?? false) {
        final orderId = result['order_id'] as String;
        logger.i('OrderRepository → createOrder complete: $orderId');
        return AppSuccess(orderId);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e(
        'OrderRepository → createOrder failed',
        error: e,
        stackTrace: st,
      );
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
      logger.i(
        'OrderRepository → fetchOrderForEdit loaded: ${order.items.length} items',
      );
      return AppSuccess(order);
    } catch (e, st) {
      logger.e(
        'OrderRepository → fetchOrderForEdit failed',
        error: e,
        stackTrace: st,
      );
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Order>> fetchOrderDetail(String orderId) async {
    try {
      logger.d('OrderRepository → fetchOrderDetail: $orderId');
      final data = await _supabase
          .from('orders')
          .select(_orderDetailSelect)
          .eq('id', orderId)
          .single();
      return AppSuccess(Order.fromMap(data));
    } catch (e, st) {
      logger.e(
        'OrderRepository → fetchOrderDetail failed',
        error: e,
        stackTrace: st,
      );
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<AuditLogEntry>>> fetchAuditLog(String orderId) async {
    try {
      logger.d('OrderRepository → fetchAuditLog: $orderId');
      final data = await _supabase
          .from('audit_log')
          .select(
            'id, order_id, action, old_status, new_status, performed_by, details, notes, server_timestamp, '
            'performer:profiles!audit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)',
          )
          .eq('order_id', orderId)
          .order('server_timestamp');
      return AppSuccess(
        (data as List)
            .map((e) => AuditLogEntry.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (e, st) {
      logger.e(
        'OrderRepository → fetchAuditLog failed',
        error: e,
        stackTrace: st,
      );
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
      final result = await _supabase.rpc(
        'edit_order_items',
        params: {
          'p_order_id': orderId,
          'p_reason': reason,
          'p_updates': updates,
          'p_removals': removals,
          'p_additions': additions,
        },
      );
      if (result['success'] as bool? ?? false) {
        logger.i(
          'OrderRepository → editOrderItems success: ${result['changes_count']} changes',
        );
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e(
        'OrderRepository → editOrderItems failed',
        error: e,
        stackTrace: st,
      );
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<OrderEditLogEntry>>> fetchEditLog(
    String orderId,
  ) async {
    try {
      logger.d('OrderRepository → fetchEditLog: $orderId');
      final data = await _supabase
          .from('order_edit_log')
          .select(
            'id, order_id, performed_by, reason, changes, server_timestamp, performer:profiles!order_edit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)',
          )
          .eq('order_id', orderId)
          .order('server_timestamp', ascending: false);
      final entries = (data as List)
          .map((e) => OrderEditLogEntry.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i(
        'OrderRepository → fetchEditLog loaded: ${entries.length} entries',
      );
      return AppSuccess(entries);
    } catch (e, st) {
      logger.e(
        'OrderRepository → fetchEditLog failed',
        error: e,
        stackTrace: st,
      );
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
