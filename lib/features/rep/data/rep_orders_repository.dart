import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';

class RepOrdersRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, '
      'entity:entities(*), '
      'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), '
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

  Future<List<Order>> fetchMyOrders() async {
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
    return orders;
  }

  Future<Order> fetchOrderDetail(String orderId) async {
    logger.d('RepOrdersRepository → fetchOrderDetail: $orderId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single();
    return Order.fromMap(data);
  }

  Future<void> startMove(String orderId, {String? notes}) async {
    logger.d('RepOrdersRepository → startMove: $orderId');
    final result = await _supabase.rpc('start_move', params: {
      'target_order_id': orderId,
      'p_notes': notes,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل بدء التنقل';
      logger.e('RepOrdersRepository → startMove failed: $error');
      throw Exception(error);
    }
    logger.i('RepOrdersRepository → startMove success: $orderId');
  }

  Future<void> markPickedUp(String orderId, {String? notes}) async {
    logger.d('RepOrdersRepository → markPickedUp: $orderId');
    final result = await _supabase.rpc('mark_picked_up', params: {
      'target_order_id': orderId,
      'p_notes': notes,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تسجيل الاستلام';
      logger.e('RepOrdersRepository → markPickedUp failed: $error');
      throw Exception(error);
    }
    logger.i('RepOrdersRepository → markPickedUp success: $orderId');
  }

  Future<void> markDelivered(String orderId, {String? notes}) async {
    logger.d('RepOrdersRepository → markDelivered: $orderId');
    final result = await _supabase.rpc('mark_delivered', params: {
      'target_order_id': orderId,
      'p_notes': notes,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تسجيل التسليم';
      logger.e('RepOrdersRepository → markDelivered failed: $error');
      throw Exception(error);
    }
    logger.i('RepOrdersRepository → markDelivered success: $orderId');
  }

  /// Returns the public URL of the uploaded receipt.
  Future<String> uploadReceipt({
    required String orderId,
    required String orderItemId,
    required File imageFile,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final ext = imageFile.path.split('.').last;
    final path = '$userId/$orderId/$orderItemId.$ext';
    logger.d('RepOrdersRepository → uploadReceipt: $path');

    await _supabase.storage.from('receipts').upload(
          path,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    final url = _supabase.storage.from('receipts').getPublicUrl(path);
    logger.d('RepOrdersRepository → receipt url: $url');

    await _supabase.from('receipts').insert({
      'order_id': orderId,
      'order_item_id': orderItemId,
      'image_url': url,
      'uploaded_by': userId,
    });

    logger.i('RepOrdersRepository → receipt saved for item $orderItemId');
    return url;
  }

  /// Fetches all receipt URLs for a given order, keyed by order_item_id.
  Future<Map<String, String>> fetchReceipts(String orderId) async {
    logger.d('RepOrdersRepository → fetchReceipts: $orderId');
    final data = await _supabase
        .from('receipts')
        .select('order_item_id, image_url')
        .eq('order_id', orderId);
    final map = <String, String>{};
    for (final row in data as List) {
      map[row['order_item_id'] as String] = row['image_url'] as String;
    }
    logger.i('RepOrdersRepository → ${map.length} receipts for order $orderId');
    return map;
  }
}
