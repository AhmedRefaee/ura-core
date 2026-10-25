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
      'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name, unit, quantity))';

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
      // The 'assigned' query above has no direction filter at the DB level,
      // so filter per order here:
      //   - outbound: every one until storage has reviewed it (✓/✗ each row).
      //     Once reviewed, an order nobody is sending stays 'assigned' for
      //     the rep but is no longer storage's to act on.
      //   - inbound_external: always -- storage confirms delivery right at
      //     'assigned', that IS this direction's storage step.
      //   - inbound_rep: never at 'assigned' -- storage only acts once the
      //     rep has bought and started moving (the second query below).
      final assignedForStorage = _map(results[0] as List).where((o) {
        return switch (o.direction) {
          OrderDirection.outbound => !o.storageReviewed,
          OrderDirection.inboundExternal => true,
          OrderDirection.inboundRep => false,
        };
      });
      final orders = [
        ...assignedForStorage,
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
              'id, order_id, action, old_status, new_status, performed_by, details, notes, server_timestamp, location_lat, location_lng, '
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

  /// Goes through the `check_order_item` RPC, which enforces server-side that
  /// the caller is storage, the order is still awaiting its review and the
  /// direction allows it -- a raw table UPDATE only ever relied on RLS.
  Future<AppResult<void>> _setItemCheckStatus(String itemId, String statusStr) async {
    try {
      logger.d('StorageRepository → check_order_item: $itemId → $statusStr');
      final result = await _supabase.rpc('check_order_item', params: {
        'target_item_id': itemId,
        'new_status': statusStr,
      });
      if (result['success'] as bool? ?? false) {
        logger.i('StorageRepository → item $itemId marked $statusStr');
        return const AppSuccess(null);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('StorageRepository → check_order_item failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> updateItemCheckStatus(String itemId, ItemCheckStatus status) =>
      _setItemCheckStatus(itemId, status == ItemCheckStatus.checked ? 'checked' : 'rejected');

  Future<AppResult<void>> revertItemCheckStatus(String itemId) =>
      _setItemCheckStatus(itemId, 'pending');

  // ── Linking a typed line ──────────────────────────────────────────────────

  /// Links a line the verifier typed to catalog row [inventoryId] (and marks
  /// it ✓), or with a null [inventoryId] unlinks it back to what was typed.
  /// [quantity] restates the line in the catalog row's unit.
  Future<AppResult<void>> linkItem(String itemId, String? inventoryId, {double? quantity}) async {
    try {
      logger.d('StorageRepository → storage_link_order_item: $itemId → $inventoryId');
      final result = await _supabase.rpc('storage_link_order_item', params: {
        'p_item_id': itemId,
        'p_inventory_id': inventoryId,
        'p_quantity': quantity,
      });
      if (result['success'] as bool? ?? false) return const AppSuccess(null);
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('StorageRepository → storage_link_order_item failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Final quantity edit ───────────────────────────────────────────────────

  Future<AppResult<void>> updateFinalQuantity(String itemId, double quantity) async {
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Order> _map(List data) =>
      data.map((e) => Order.fromMap(e as Map<String, dynamic>)).toList();
}
