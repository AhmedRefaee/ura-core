import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';

class StorageRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, '
      'entity:entities(*), '
      'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), '
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

  // ── Active queue (storage actor's turn) ───────────────────────────────────

  /// Flow 1 & 4: assigned orders (outbound-storage + inbound_external)
  /// Flow 3: on_the_move inbound_rep orders (rep is bringing goods to storage)
  Future<List<Order>> fetchActiveForStorage() async {
    logger.d('StorageRepository → fetchActiveForStorage');
    final results = await Future.wait([
      _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('status', 'assigned')
          .order('created_at', ascending: true),
      _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('status', 'on_the_move')
          .eq('direction', 'inbound_rep')
          .order('created_at', ascending: true),
    ]);
    final orders = [
      ..._map(results[0] as List),
      ..._map(results[1] as List),
    ];
    logger.i('StorageRepository → ${orders.length} active orders for storage');
    return orders;
  }

  /// Orders this storage actor has already completed (via storage_actor_id).
  Future<List<Order>> fetchDoneByStorageActor(String userId) async {
    logger.d('StorageRepository → fetchDoneByStorageActor: $userId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('storage_actor_id', userId)
        .eq('status', 'delivered')
        .order('delivered_at', ascending: false);
    final orders = _map(data as List);
    logger.i('StorageRepository → ${orders.length} done orders for $userId');
    return orders;
  }

  // ── Order detail ──────────────────────────────────────────────────────────

  Future<Order> fetchOrderDetail(String orderId) async {
    logger.d('StorageRepository → fetchOrderDetail: $orderId');
    final data = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single();
    return Order.fromMap(data);
  }

  // ── Item check status ─────────────────────────────────────────────────────

  Future<void> updateItemCheckStatus(
      String itemId, ItemCheckStatus status) async {
    final statusStr =
        status == ItemCheckStatus.checked ? 'checked' : 'rejected';
    logger.d('StorageRepository → updateItemCheckStatus: $itemId → $statusStr');
    await _supabase.from('order_items').update({
      'check_status': statusStr,
      'checked_by': _supabase.auth.currentUser!.id,
      'checked_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', itemId);
    logger.i('StorageRepository → item $itemId marked $statusStr');
  }

  Future<void> revertItemCheckStatus(String itemId) async {
    logger.d('StorageRepository → revertItemCheckStatus: $itemId → pending');
    await _supabase.from('order_items').update({
      'check_status': 'pending',
      'checked_by': null,
      'checked_at': null,
    }).eq('id', itemId);
    logger.i('StorageRepository → item $itemId reverted to pending');
  }

  // ── Final quantity edit ───────────────────────────────────────────────────

  Future<void> updateFinalQuantity(String itemId, int quantity) async {
    logger.d('StorageRepository → updateFinalQuantity: $itemId → $quantity');
    await _supabase
        .from('order_items')
        .update({'final_quantity': quantity}).eq('id', itemId);
    logger.i('StorageRepository → final_quantity set for $itemId');
  }

  // ── Confirm actions (inventory-changing) ──────────────────────────────────

  /// Flow 1 (outbound + storage): decreases inventory, sets status → picked_up.
  Future<void> confirmPickup(
    String orderId, {
    String? notes,
    List<Map<String, dynamic>> finalQuantities = const [],
  }) async {
    logger.d('StorageRepository → confirmPickup: $orderId');
    final result = await _supabase.rpc('storage_confirm_pickup', params: {
      'target_order_id': orderId,
      'p_notes': notes,
      'p_final_quantities': finalQuantities,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تأكيد الإرسال';
      logger.e('StorageRepository → confirmPickup failed: $error');
      throw Exception(error);
    }
    logger.i('StorageRepository → confirmPickup success: $orderId');
  }

  /// Flow 3 & 4 (inbound): increases inventory, sets status → delivered.
  Future<void> confirmDelivery(
    String orderId, {
    String? notes,
    List<Map<String, dynamic>> finalQuantities = const [],
  }) async {
    logger.d('StorageRepository → confirmDelivery: $orderId');
    final result = await _supabase.rpc('storage_confirm_delivery', params: {
      'target_order_id': orderId,
      'p_notes': notes,
      'p_final_quantities': finalQuantities,
    });
    final success = result['success'] as bool? ?? false;
    if (!success) {
      final error = result['error'] as String? ?? 'فشل تأكيد الاستلام';
      logger.e('StorageRepository → confirmDelivery failed: $error');
      throw Exception(error);
    }
    logger.i('StorageRepository → confirmDelivery success: $orderId');
  }

  // ── Receipt upload (Flow 4 — inbound_external) ────────────────────────────

  Future<String> uploadReceipt({
    required String orderId,
    required String orderItemId,
    required File imageFile,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final ext = imageFile.path.split('.').last;
    final path = '$userId/$orderId/$orderItemId.$ext';
    logger.d('StorageRepository → uploadReceipt: $path');

    await _supabase.storage.from('receipts').upload(
          path,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    final url = _supabase.storage.from('receipts').getPublicUrl(path);

    await _supabase.from('receipts').insert({
      'order_id': orderId,
      'order_item_id': orderItemId,
      'image_url': url,
      'uploaded_by': userId,
    });

    logger.i('StorageRepository → receipt saved for item $orderItemId');
    return url;
  }

  Future<Map<String, String>> fetchReceipts(String orderId) async {
    logger.d('StorageRepository → fetchReceipts: $orderId');
    final data = await _supabase
        .from('receipts')
        .select('order_item_id, image_url')
        .eq('order_id', orderId);
    final map = <String, String>{};
    for (final row in data as List) {
      map[row['order_item_id'] as String] = row['image_url'] as String;
    }
    return map;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Order> _map(List data) =>
      data.map((e) => Order.fromMap(e as Map<String, dynamic>)).toList();
}
