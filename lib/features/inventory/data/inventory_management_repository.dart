import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/cache/memory_cache.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_audit_log_entry.dart';
import '../../../shared/models/inventory_item.dart';

class InventoryManagementRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _inventoryCache = MemoryCache<String, List<InventoryItem>>(ttl: Duration(minutes: 2));

  Future<AppResult<List<InventoryItem>>> fetchInventory({
    String? search,
    String? category,
  }) async {
    try {
      final cacheKey = 'inventory:${search ?? ''}:${category ?? ''}';
      final cached = _inventoryCache.get(cacheKey);
      if (cached != null) {
        logger.d('fetchInventory → cache hit: $cacheKey');
        return AppSuccess(cached);
      }
      
      var query = _supabase
          .from('inventory')
          .select('id, item_name, sku, quantity, unit, category, min_quantity, description');
      if (search != null && search.isNotEmpty) {
        query = query.ilike('item_name', '%$search%');
      }
      if (category != null) {
        query = query.eq('category', category);
      }
      final data = await query.order('item_name');
      final result = (data as List).map((m) => InventoryItem.fromMap(m as Map<String, dynamic>)).toList();
      _inventoryCache.set(cacheKey, result);
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('fetchInventory failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<InventoryItem>> fetchItemDetail(String itemId) async {
    try {
      final data = await _supabase
          .from('inventory')
          .select('id, item_name, sku, quantity, unit, category, min_quantity, description')
          .eq('id', itemId)
          .single();
      return AppSuccess(InventoryItem.fromMap(data));
    } catch (e, st) {
      logger.e('fetchItemDetail failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<InventoryAuditLogEntry>>> fetchAuditLog(String itemId) async {
    try {
      final data = await _supabase
          .from('inventory_audit_log')
          .select('id, item_id, action, old_quantity, new_quantity, performed_by, notes, performed_at, performer:profiles!inventory_audit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)')
          .eq('item_id', itemId)
          .order('performed_at', ascending: false);
      return AppSuccess(
        (data as List)
            .map((m) => InventoryAuditLogEntry.fromMap(m as Map<String, dynamic>))
            .toList(),
      );
    } catch (e, st) {
      logger.e('fetchAuditLog failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> createItem({
    required String name,
    required String unit,
    required int quantity,
    String? sku,
    String? category,
    int minQuantity = 0,
    String? description,
    String? notes,
  }) async {
    try {
      final result = await _supabase.rpc('inventory_create_item', params: {
        'p_name': name,
        'p_unit': unit,
        'p_quantity': quantity,
        'p_sku': sku,
        'p_category': category,
        'p_min_quantity': minQuantity,
        'p_description': description,
        'p_notes': notes,
      });
      if (result is Map && result['success'] == false) {
        return AppFailure(ErrorHandler.fromRpcResult(result));
      }
      _inventoryCache.clear();
      logger.i('Inventory item created: $name');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('createItem failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> updateItem(
    String itemId, {
    required String name,
    required String unit,
    required int quantity,
    String? sku,
    String? category,
    int minQuantity = 0,
    String? description,
    String? notes,
  }) async {
    try {
      final result = await _supabase.rpc('inventory_update_item', params: {
        'p_item_id': itemId,
        'p_name': name,
        'p_unit': unit,
        'p_quantity': quantity,
        'p_sku': sku,
        'p_category': category,
        'p_min_quantity': minQuantity,
        'p_description': description,
        'p_notes': notes,
      });
      if (result is Map && result['success'] == false) {
        return AppFailure(ErrorHandler.fromRpcResult(result));
      }
      _inventoryCache.clear();
      logger.i('Inventory item updated: $itemId');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('updateItem failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteItem(String itemId) async {
    try {
      final result = await _supabase.rpc('inventory_delete_item', params: {
        'p_item_id': itemId,
      });
      if (result is Map && result['success'] == false) {
        return AppFailure(ErrorHandler.fromRpcResult(result));
      }
      _inventoryCache.clear();
      logger.i('Inventory item deleted: $itemId');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('deleteItem failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> bulkUpdateQuantities(
    List<({String itemId, int quantity})> updates,
  ) async {
    try {
      final payload = updates
          .map((u) => {'item_id': u.itemId, 'quantity': u.quantity})
          .toList();
      final result = await _supabase.rpc('inventory_bulk_update_quantities', params: {
        'p_updates': payload,
      });
      if (result is Map && result['success'] == false) {
        return AppFailure(ErrorHandler.fromRpcResult(result));
      }
      _inventoryCache.clear();
      logger.i('Bulk quantity update: ${updates.length} items');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('bulkUpdateQuantities failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Set<String>>> fetchExistingSkus() async {
    try {
      final data = await _supabase
          .from('inventory')
          .select('sku')
          .not('sku', 'is', null);
      final skus = (data as List)
          .map((row) => (row['sku'] as String).toLowerCase())
          .toSet();
      return AppSuccess(skus);
    } catch (e, st) {
      logger.e('fetchExistingSkus failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> bulkImportItems(
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      await _supabase.from('inventory').insert(rows);
      _inventoryCache.clear();
      logger.i('Bulk import: ${rows.length} items inserted');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('bulkImportItems failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<InventoryItem>>> fetchAllForExport() async {
    try {
      final data = await _supabase
          .from('inventory')
          .select('id, item_name, sku, quantity, unit, category, min_quantity, description, notes')
          .order('item_name');
      final result = (data as List)
          .map((m) => InventoryItem.fromMap(m as Map<String, dynamic>))
          .toList();
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('fetchAllForExport failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> bulkUpdateItems(
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      for (final row in rows) {
        final id = row['id'] as String;
        final data = Map<String, dynamic>.from(row)..remove('id');
        await _supabase.from('inventory').update(data).eq('id', id);
      }
      _inventoryCache.clear();
      logger.i('Bulk update: ${rows.length} items updated');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('bulkUpdateItems failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
