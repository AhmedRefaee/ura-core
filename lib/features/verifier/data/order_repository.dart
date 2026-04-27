import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
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

  Future<List<Order>> fetchAllOrders() async {
    logger.d('OrderRepository → fetchAllOrders');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .order('created_at', ascending: false);
    final orders = (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('OrderRepository → loaded ${orders.length} orders');
    return orders;
  }

  Future<List<Profile>> fetchReps() async {
    logger.d('OrderRepository → fetchReps');
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'rep')
        .eq('is_approved', true)
        .order('full_name');
    final reps = (data as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('OrderRepository → loaded ${reps.length} reps');
    return reps;
  }

  Future<List<Profile>> fetchPendingUsers() async {
    logger.d('OrderRepository → fetchPendingUsers');
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('is_approved', false)
        .order('created_at');
    final users = (data as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('OrderRepository → ${users.length} pending users');
    return users;
  }

  Future<void> approveUser(String userId, String role) async {
    logger.d('OrderRepository → approveUser: $userId | role: $role');
    final result = await _supabase.rpc('approve_user', params: {
      'target_user_id': userId,
      'assigned_role': role,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تفعيل المستخدم';
      logger.e('OrderRepository → approveUser failed: $error');
      throw Exception(error);
    }
    logger.i('OrderRepository → approveUser success: $userId as $role');
  }

  Future<String> createOrder({
    required String direction,
    required String entityId,
    String? repId,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
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

    final itemRows = items
        .map((item) => {
              'order_id': orderId,
              ...item,
            })
        .toList();

    await _supabase.from('order_items').insert(itemRows);
    logger.i('OrderRepository → createOrder complete: $orderId');
    return orderId;
  }

  Future<Order> fetchOrderForEdit(String orderId) async {
    logger.d('OrderRepository → fetchOrderForEdit: $orderId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single();
    final order = Order.fromMap(data);
    logger.i('OrderRepository → fetchOrderForEdit loaded: ${order.items.length} items');
    return order;
  }

  Future<void> editOrderItems({
    required String orderId,
    required String reason,
    List<Map<String, dynamic>> updates = const [],
    List<String> removals = const [],
    List<Map<String, dynamic>> additions = const [],
  }) async {
    logger.d('OrderRepository → editOrderItems: $orderId | reason: $reason');
    final result = await _supabase.rpc('edit_order_items', params: {
      'p_order_id': orderId,
      'p_reason': reason,
      'p_updates': updates,
      'p_removals': removals,
      'p_additions': additions,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تعديل الطلب';
      logger.e('OrderRepository → editOrderItems failed: $error');
      throw Exception(error);
    }
    logger.i('OrderRepository → editOrderItems success: ${result['changes_count']} changes');
  }

  Future<List<OrderEditLogEntry>> fetchEditLog(String orderId) async {
    logger.d('OrderRepository → fetchEditLog: $orderId');
    final data = await _supabase
        .from('order_edit_log')
        .select('*, performer:profiles!order_edit_log_performed_by_fkey(id, full_name, role)')
        .eq('order_id', orderId)
        .order('server_timestamp', ascending: false);
    final entries = (data as List)
        .map((e) => OrderEditLogEntry.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('OrderRepository → fetchEditLog loaded: ${entries.length} entries');
    return entries;
  }

  /// Fetches all receipt URLs for a given order, keyed by order_item_id.
  Future<Map<String, String>> fetchReceipts(String orderId) async {
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
    return map;
  }
}
