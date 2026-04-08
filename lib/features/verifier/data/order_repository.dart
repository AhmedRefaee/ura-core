import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/profile.dart';

class OrderRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, entity:entities(*), rep:profiles!orders_rep_id_fkey(*), order_items(*, inventory:inventory(id, item_name))';

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
          if (repId != null) 'rep_id': repId,
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
}
