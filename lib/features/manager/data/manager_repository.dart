import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/cache/memory_cache.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/notifications/notification_dispatcher.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';

class ManagerRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _repListCache = MemoryCache<String, List<Profile>>(ttl: Duration(minutes: 3));
  final _pendingUsersCache = MemoryCache<String, List<Profile>>(ttl: Duration(minutes: 3));

  static const _orderSelect =
      'id, direction, entity_id, rep_id, created_by, storage_actor_id, status, notes, created_at, assigned_at, picked_up_at, move_started_at, delivered_at, entity:entities(id, name, category, contact_name, contact_phone, address), rep:profiles!orders_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), creator:profiles!orders_created_by_fkey(id, full_name, phone, role, is_approved, created_at), order_items(id, order_id, inventory_id, quantity, final_quantity, is_custom, custom_description, source_inventory_id, check_status, checked_by, checked_at, inventory:inventory!order_items_inventory_id_fkey(id, item_name), checker:profiles!order_items_checked_by_fkey(id, full_name, phone, role, is_approved, created_at))';

  // ── Users ──────────────────────────────────────────────────────────────────

  Future<AppResult<List<Profile>>> fetchUsersByRole(String role) async {
    try {
      final cacheKey = 'rep_list:$role';
      final cached = _repListCache.get(cacheKey);
      if (cached != null) {
        logger.d('ManagerRepository → fetchUsersByRole: $role (cache hit)');
        return AppSuccess(cached);
      }
      
      logger.d('ManagerRepository → fetchUsersByRole: $role');
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved, created_at')
          .eq('role', role)
          .eq('is_approved', true)
          .order('full_name');
      final result = (data as List)
          .map((e) => Profile.fromMap(e as Map<String, dynamic>))
          .toList();
      _repListCache.set(cacheKey, result);
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('ManagerRepository → fetchUsersByRole failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Profile>>> fetchPendingUsers() async {
    try {
      final cacheKey = 'pending_users';
      final cached = _pendingUsersCache.get(cacheKey);
      if (cached != null) {
        logger.d('ManagerRepository → fetchPendingUsers (cache hit)');
        return AppSuccess(cached);
      }
      
      logger.d('ManagerRepository → fetchPendingUsers');
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved, created_at')
          .eq('is_approved', false)
          .order('created_at');
      final result = (data as List)
          .map((e) => Profile.fromMap(e as Map<String, dynamic>))
          .toList();
      _pendingUsersCache.set(cacheKey, result);
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('ManagerRepository → fetchPendingUsers failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> approveUser(String userId, String role) async {
    try {
      logger.d('ManagerRepository → approveUser: $userId as $role');
      final result = await _supabase.rpc('approve_user', params: {
        'target_user_id': userId,
        'assigned_role': role,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('ManagerRepository → approveUser success: $userId as $role');
        _repListCache.invalidate('rep_list:$role');
        _pendingUsersCache.invalidate('pending_users');
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
      logger.e('ManagerRepository → approveUser failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Map<String, OrderStatus>>> fetchLatestOrderStatusByRep() async {
    try {
      logger.d('ManagerRepository → fetchLatestOrderStatusByRep');
      final data = await _supabase
          .from('orders')
          .select('rep_id, status, created_at')
          .not('rep_id', 'is', null)
          .order('created_at', ascending: false);

      final Map<String, OrderStatus> result = {};
      for (final row in data as List) {
        final repId = row['rep_id'] as String?;
        if (repId != null && !result.containsKey(repId)) {
          result[repId] = Order.statusFromString(row['status'] as String);
        }
      }
      logger.i('ManagerRepository → latest status for ${result.length} reps');
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('ManagerRepository → fetchLatestOrderStatusByRep failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Orders by user ─────────────────────────────────────────────────────────

  Future<AppResult<List<Order>>> fetchOrdersByRep(String repId) async {
    try {
      logger.d('ManagerRepository → fetchOrdersByRep: $repId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('rep_id', repId)
          .order('created_at', ascending: false);
      return AppSuccess(_mapOrders(data));
    } catch (e, st) {
      logger.e('ManagerRepository → fetchOrdersByRep failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Order>>> fetchOrdersByCreator(String userId) async {
    try {
      logger.d('ManagerRepository → fetchOrdersByCreator: $userId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('created_by', userId)
          .order('created_at', ascending: false);
      return AppSuccess(_mapOrders(data));
    } catch (e, st) {
      logger.e('ManagerRepository → fetchOrdersByCreator failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Order>>> fetchOrdersByStorageActor(String userId) async {
    try {
      logger.d('ManagerRepository → fetchOrdersByStorageActor: $userId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('storage_actor_id', userId)
          .order('created_at', ascending: false);
      final orders = _mapOrders(data);
      if (orders.isNotEmpty) return AppSuccess(orders);

      logger.d('ManagerRepository → fetchOrdersByStorageActor: fallback to checked_by');
      final itemsData = await _supabase
          .from('order_items')
          .select('order_id')
          .eq('checked_by', userId);
      final orderIds = (itemsData as List)
          .map((e) => e['order_id'] as String)
          .toSet()
          .toList();
      if (orderIds.isEmpty) return const AppSuccess([]);
      final fallback = await _supabase
          .from('orders')
          .select(_orderSelect)
          .inFilter('id', orderIds)
          .order('created_at', ascending: false);
      return AppSuccess(_mapOrders(fallback));
    } catch (e, st) {
      logger.e('ManagerRepository → fetchOrdersByStorageActor failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── All orders ────────────────────────────────────────────────────────────

  Future<AppResult<List<Order>>> fetchActiveOrders() async {
    try {
      logger.d('ManagerRepository → fetchActiveOrders');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .neq('status', 'delivered')
          .order('created_at', ascending: false)
          .limit(150);
      return AppSuccess(_mapOrders(data));
    } catch (e, st) {
      logger.e('ManagerRepository → fetchActiveOrders failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Order>>> fetchFinishedOrders({
    int page = 0,
    int pageSize = 30,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;
      logger.d('ManagerRepository → fetchFinishedOrders page=$page');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('status', 'delivered')
          .order('delivered_at', ascending: false)
          .range(from, to);
      return AppSuccess(_mapOrders(data));
    } catch (e, st) {
      logger.e('ManagerRepository → fetchFinishedOrders failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Task detail ────────────────────────────────────────────────────────────

  Future<AppResult<Order>> fetchOrderDetail(String orderId) async {
    try {
      logger.d('ManagerRepository → fetchOrderDetail: $orderId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('id', orderId)
          .single();
      return AppSuccess(Order.fromMap(data));
    } catch (e, st) {
      logger.e('ManagerRepository → fetchOrderDetail failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<AuditLogEntry>>> fetchAuditLog(String orderId) async {
    try {
      logger.d('ManagerRepository → fetchAuditLog: $orderId');
      final data = await _supabase
          .from('audit_log')
          .select('id, order_id, action, old_status, new_status, performed_by, details, notes, server_timestamp, performer:profiles!audit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)')
          .eq('order_id', orderId)
          .order('server_timestamp');
      return AppSuccess((data as List)
          .map((e) => AuditLogEntry.fromMap(e as Map<String, dynamic>))
          .toList());
    } catch (e, st) {
      logger.e('ManagerRepository → fetchAuditLog failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Map<String, String>>> fetchReceipts(String orderId) async {
    try {
      logger.d('ManagerRepository → fetchReceipts: $orderId');
      final data = await _supabase
          .from('receipts')
          .select('order_item_id, image_url')
          .eq('order_id', orderId);
      final map = <String, String>{};
      for (final row in data as List) {
        map[row['order_item_id'] as String] = row['image_url'] as String;
      }
      logger.i('ManagerRepository → ${map.length} receipts for order $orderId');
      return AppSuccess(map);
    } catch (e, st) {
      logger.e('ManagerRepository → fetchReceipts failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Delete order ──────────────────────────────────────────────────────────

  Future<AppResult<void>> deleteOrder(String orderId) async {
    try {
      logger.d('ManagerRepository → deleteOrder: $orderId');
      await _supabase.from('audit_log').delete().eq('order_id', orderId);
      await _supabase.from('order_items').delete().eq('order_id', orderId);
      await _supabase.from('orders').delete().eq('id', orderId);
      final check = await _supabase
          .from('orders')
          .select('id')
          .eq('id', orderId)
          .maybeSingle();
      if (check != null) {
        logger.e('ManagerRepository → deleteOrder blocked (RLS or FK): $orderId');
        return const AppFailure(AppError(
          message: 'فشل حذف الطلب — تحقق من الصلاحيات',
          type: AppErrorType.permission,
        ));
      }
      logger.i('ManagerRepository → deleteOrder success: $orderId');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ManagerRepository → deleteOrder failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Order> _mapOrders(List<dynamic> data) => data
      .map((e) => Order.fromMap(e as Map<String, dynamic>))
      .toList();
}
