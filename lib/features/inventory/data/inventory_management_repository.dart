import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_audit_log_entry.dart';
import '../../../shared/models/inventory_item.dart';

class InventoryManagementRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Public (all roles) ──────────────────────────────────────────────────────

  Future<List<InventoryItem>> fetchInventory({
    String? search,
    String? category,
  }) async {
    try {
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
      return (data as List).map((m) => InventoryItem.fromMap(m as Map<String, dynamic>)).toList();
    } catch (e, st) {
      logger.e('fetchInventory failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ── Storage Actor — read ────────────────────────────────────────────────────

  Future<InventoryItem> fetchItemDetail(String itemId) async {
    try {
      final data = await _supabase
          .from('inventory')
          .select('id, item_name, sku, quantity, unit, category, min_quantity, description')
          .eq('id', itemId)
          .single();
      return InventoryItem.fromMap(data);
    } catch (e, st) {
      logger.e('fetchItemDetail failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<List<InventoryAuditLogEntry>> fetchAuditLog(String itemId) async {
    try {
      final data = await _supabase
          .from('inventory_audit_log')
          .select('*, performer:profiles!inventory_audit_log_performed_by_fkey(id, full_name, role)')
          .eq('item_id', itemId)
          .order('performed_at', ascending: false);
      return (data as List)
          .map((m) => InventoryAuditLogEntry.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      logger.e('fetchAuditLog failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ── Storage Actor — CRUD ────────────────────────────────────────────────────

  Future<void> createItem({
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
        throw Exception(result['error'] ?? 'فشل إنشاء العنصر');
      }
      logger.i('Inventory item created: $name');
    } catch (e, st) {
      logger.e('createItem failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateItem(
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
        throw Exception(result['error'] ?? 'فشل تعديل العنصر');
      }
      logger.i('Inventory item updated: $itemId');
    } catch (e, st) {
      logger.e('updateItem failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteItem(String itemId) async {
    try {
      final result = await _supabase.rpc('inventory_delete_item', params: {
        'p_item_id': itemId,
      });
      if (result is Map && result['success'] == false) {
        throw Exception(result['error'] ?? 'فشل حذف العنصر');
      }
      logger.i('Inventory item deleted: $itemId');
    } catch (e, st) {
      logger.e('deleteItem failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> bulkUpdateQuantities(
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
        throw Exception(result['error'] ?? 'فشل التعديل الجماعي');
      }
      logger.i('Bulk quantity update: ${updates.length} items');
    } catch (e, st) {
      logger.e('bulkUpdateQuantities failed', error: e, stackTrace: st);
      rethrow;
    }
  }
}
