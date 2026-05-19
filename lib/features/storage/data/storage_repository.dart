import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';

class StorageRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _orderSelect =
      '*, '
      'entity:entities(*), '
      'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), '
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

  // ── Active queue ──────────────────────────────────────────────────────────

  Future<AppResult<List<Order>>> fetchActiveForStorage() async {
    try {
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
      return AppSuccess(orders);
    } catch (e, st) {
      logger.e('StorageRepository → fetchActiveForStorage failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Order>>> fetchDoneByStorageActor(String userId) async {
    try {
      logger.d('StorageRepository → fetchDoneByStorageActor: $userId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('storage_actor_id', userId)
          .eq('status', 'delivered')
          .order('delivered_at', ascending: false);
      final orders = _map(data as List);
      logger.i('StorageRepository → ${orders.length} done orders for $userId');
      return AppSuccess(orders);
    } catch (e, st) {
      logger.e('StorageRepository → fetchDoneByStorageActor failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Audit log ─────────────────────────────────────────────────────────────

  Future<AppResult<List<AuditLogEntry>>> fetchAuditLog(String orderId) async {
    try {
      logger.d('StorageRepository → fetchAuditLog: $orderId');
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
      logger.e('StorageRepository → fetchAuditLog failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Order detail ──────────────────────────────────────────────────────────

  Future<AppResult<Order>> fetchOrderDetail(String orderId) async {
    try {
      logger.d('StorageRepository → fetchOrderDetail: $orderId');
      final data = await _supabase
          .from('orders')
          .select(_orderSelect)
          .eq('id', orderId)
          .single();
      return AppSuccess(Order.fromMap(data));
    } catch (e, st) {
      logger.e('StorageRepository → fetchOrderDetail failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Item check status ─────────────────────────────────────────────────────

  Future<AppResult<void>> updateItemCheckStatus(String itemId, ItemCheckStatus status) async {
    try {
      final statusStr = status == ItemCheckStatus.checked ? 'checked' : 'rejected';
      logger.d('StorageRepository → updateItemCheckStatus: $itemId → $statusStr');
      await _supabase.from('order_items').update({
        'check_status': statusStr,
        'checked_by': _supabase.auth.currentUser!.id,
        'checked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', itemId);
      logger.i('StorageRepository → item $itemId marked $statusStr');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('StorageRepository → updateItemCheckStatus failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> revertItemCheckStatus(String itemId) async {
    try {
      logger.d('StorageRepository → revertItemCheckStatus: $itemId → pending');
      await _supabase.from('order_items').update({
        'check_status': 'pending',
        'checked_by': null,
        'checked_at': null,
      }).eq('id', itemId);
      logger.i('StorageRepository → item $itemId reverted to pending');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('StorageRepository → revertItemCheckStatus failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Final quantity edit ───────────────────────────────────────────────────

  Future<AppResult<void>> updateFinalQuantity(String itemId, int quantity) async {
    try {
      logger.d('StorageRepository → updateFinalQuantity: $itemId → $quantity');
      await _supabase
          .from('order_items')
          .update({'final_quantity': quantity}).eq('id', itemId);
      logger.i('StorageRepository → final_quantity set for $itemId');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('StorageRepository → updateFinalQuantity failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Confirm actions ───────────────────────────────────────────────────────

  Future<AppResult<void>> confirmPickup(
    String orderId, {
    String? notes,
    List<Map<String, dynamic>> finalQuantities = const [],
  }) async {
    try {
      logger.d('StorageRepository → confirmPickup: $orderId');
      final result = await _supabase.rpc('storage_confirm_pickup', params: {
        'target_order_id': orderId,
        'p_notes': notes,
        'p_final_quantities': finalQuantities,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('StorageRepository → confirmPickup success: $orderId');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('StorageRepository → confirmPickup failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> confirmDelivery(
    String orderId, {
    String? notes,
    List<Map<String, dynamic>> finalQuantities = const [],
  }) async {
    try {
      logger.d('StorageRepository → confirmDelivery: $orderId');
      final result = await _supabase.rpc('storage_confirm_delivery', params: {
        'target_order_id': orderId,
        'p_notes': notes,
        'p_final_quantities': finalQuantities,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('StorageRepository → confirmDelivery success: $orderId');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('StorageRepository → confirmDelivery failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Receipt upload ────────────────────────────────────────────────────────

  Future<AppResult<String>> uploadReceipt({
    required String orderId,
    required String orderItemId,
    required File imageFile,
  }) async {
    try {
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
      return AppSuccess(url);
    } catch (e, st) {
      logger.e('StorageRepository → uploadReceipt failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Map<String, String>>> fetchReceipts(String orderId) async {
    try {
      logger.d('StorageRepository → fetchReceipts: $orderId');
      final data = await _supabase
          .from('receipts')
          .select('order_item_id, image_url')
          .eq('order_id', orderId);
      final map = <String, String>{};
      for (final row in data as List) {
        map[row['order_item_id'] as String] = row['image_url'] as String;
      }
      return AppSuccess(map);
    } catch (e, st) {
      logger.e('StorageRepository → fetchReceipts failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Order> _map(List data) =>
      data.map((e) => Order.fromMap(e as Map<String, dynamic>)).toList();
}
