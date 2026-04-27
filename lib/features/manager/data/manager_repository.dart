import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';

class ManagerRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Includes creator profile and item checker profiles for full audit trail
  static const _orderSelect =
      '*, entity:entities(*), rep:profiles!orders_rep_id_fkey(*), creator:profiles!orders_created_by_fkey(id, full_name, role), order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name), checker:profiles!order_items_checked_by_fkey(id, full_name, role))';

  // ── Users ──────────────────────────────────────────────────────────────────

  Future<List<Profile>> fetchUsersByRole(String role) async {
    logger.d('ManagerRepository → fetchUsersByRole: $role');
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', role)
        .eq('is_approved', true)
        .order('full_name');
    return (data as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Profile>> fetchPendingUsers() async {
    logger.d('ManagerRepository → fetchPendingUsers');
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('is_approved', false)
        .order('created_at');
    return (data as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveUser(String userId, String role) async {
    logger.d('ManagerRepository → approveUser: $userId as $role');
    final result = await _supabase.rpc('approve_user', params: {
      'target_user_id': userId,
      'assigned_role': role,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تفعيل المستخدم';
      logger.e('ManagerRepository → approveUser failed: $error');
      throw Exception(error);
    }
    logger.i('ManagerRepository → approveUser success: $userId as $role');
  }

  /// Returns a map of rep_id → their most recent order status.
  Future<Map<String, OrderStatus>> fetchLatestOrderStatusByRep() async {
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
    return result;
  }

  // ── Orders by user ─────────────────────────────────────────────────────────

  Future<List<Order>> fetchOrdersByRep(String repId) async {
    logger.d('ManagerRepository → fetchOrdersByRep: $repId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('rep_id', repId)
        .order('created_at', ascending: false);
    return _mapOrders(data);
  }

  Future<List<Order>> fetchOrdersByCreator(String userId) async {
    logger.d('ManagerRepository → fetchOrdersByCreator: $userId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('created_by', userId)
        .order('created_at', ascending: false);
    return _mapOrders(data);
  }

  Future<List<Order>> fetchOrdersByStorageActor(String userId) async {
    logger.d('ManagerRepository → fetchOrdersByStorageActor: $userId');
    // Primary: query by storage_actor_id (set when storage actor confirms action)
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('storage_actor_id', userId)
        .order('created_at', ascending: false);
    final orders = _mapOrders(data);
    if (orders.isNotEmpty) return orders;

    // Fallback for legacy records: look up via order_items.checked_by
    logger.d('ManagerRepository → fetchOrdersByStorageActor: fallback to checked_by');
    final itemsData = await _supabase
        .from('order_items')
        .select('order_id')
        .eq('checked_by', userId);
    final orderIds = (itemsData as List)
        .map((e) => e['order_id'] as String)
        .toSet()
        .toList();
    if (orderIds.isEmpty) return [];
    final fallback = await _supabase
        .from('orders')
        .select(_orderSelect)
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);
    return _mapOrders(fallback);
  }

  // ── All orders (task monitor view) ────────────────────────────────────────

  Future<List<Order>> fetchActiveOrders() async {
    logger.d('ManagerRepository → fetchActiveOrders');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .neq('status', 'delivered')
        .order('created_at', ascending: false);
    return _mapOrders(data);
  }

  Future<List<Order>> fetchFinishedOrders() async {
    logger.d('ManagerRepository → fetchFinishedOrders');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('status', 'delivered')
        .order('delivered_at', ascending: false);
    return _mapOrders(data);
  }

  // ── Task detail ────────────────────────────────────────────────────────────

  Future<Order> fetchOrderDetail(String orderId) async {
    logger.d('ManagerRepository → fetchOrderDetail: $orderId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single();
    return Order.fromMap(data);
  }

  Future<List<AuditLogEntry>> fetchAuditLog(String orderId) async {
    logger.d('ManagerRepository → fetchAuditLog: $orderId');
    final data = await _supabase
        .from('audit_log')
        .select('*, performer:profiles!audit_log_performed_by_fkey(id, full_name, role)')
        .eq('order_id', orderId)
        .order('server_timestamp');
    return (data as List)
        .map((e) => AuditLogEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches all receipt URLs for a given order, keyed by order_item_id.
  Future<Map<String, String>> fetchReceipts(String orderId) async {
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
    return map;
  }

  // ── Delete order ──────────────────────────────────────────────────────────

  Future<void> deleteOrder(String orderId) async {
    logger.d('ManagerRepository → deleteOrder: $orderId');
    await _supabase.from('audit_log').delete().eq('order_id', orderId);
    logger.d('ManagerRepository → deleteOrder: audit_log cleared');
    await _supabase.from('order_items').delete().eq('order_id', orderId);
    logger.d('ManagerRepository → deleteOrder: order_items cleared');
    await _supabase.from('orders').delete().eq('id', orderId);
    // Verify the row is actually gone (silent RLS block returns no error)
    final check = await _supabase
        .from('orders')
        .select('id')
        .eq('id', orderId)
        .maybeSingle();
    if (check != null) {
      logger.e('ManagerRepository → deleteOrder blocked (RLS or FK): $orderId');
      throw Exception('فشل حذف الطلب — تحقق من الصلاحيات');
    }
    logger.i('ManagerRepository → deleteOrder success: $orderId');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Order> _mapOrders(List<dynamic> data) => data
      .map((e) => Order.fromMap(e as Map<String, dynamic>))
      .toList();
}
