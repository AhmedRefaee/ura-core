import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';

class StorageRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, entity:entities(*), order_items(*, inventory:inventory(id, item_name))';

  Future<List<Order>> fetchAssignedOrders() async {
    logger.d('StorageRepository → fetchAssignedOrders');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('status', 'assigned')
        .order('created_at', ascending: true);
    final orders = (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('StorageRepository → ${orders.length} assigned orders');
    return orders;
  }

  Future<Order> fetchOrderDetail(String orderId) async {
    logger.d('StorageRepository → fetchOrderDetail: $orderId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single();
    return Order.fromMap(data);
  }

  Future<void> updateItemCheckStatus(
      String itemId, ItemCheckStatus status) async {
    final statusStr =
        status == ItemCheckStatus.checked ? 'checked' : 'rejected';
    logger.d('StorageRepository → updateItemCheckStatus: $itemId → $statusStr');
    await _supabase
        .from('order_items')
        .update({'check_status': statusStr}).eq('id', itemId);
    logger.i('StorageRepository → item $itemId marked $statusStr');
  }

  Future<void> revertItemCheckStatus(String itemId) async {
    logger.d('StorageRepository → revertItemCheckStatus: $itemId → pending');
    await _supabase
        .from('order_items')
        .update({'check_status': 'pending'}).eq('id', itemId);
    logger.i('StorageRepository → item $itemId reverted to pending');
  }

  Future<void> approveOrder(String orderId) async {
    logger.d('StorageRepository → approveOrder: $orderId');
    final result = await _supabase
        .rpc('approve_order', params: {'target_order_id': orderId});
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل اعتماد الطلب';
      logger.e('StorageRepository → approveOrder failed: $error');
      throw Exception(error);
    }
    logger.i('StorageRepository → approveOrder success: $orderId');
  }
}
