import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';

class InventoryRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<InventoryItem>> fetchInventory() async {
    logger.d('InventoryRepository → fetchInventory');
    final data = await _supabase
        .from('inventory')
        .select('id, item_name, sku, quantity, unit, category, min_quantity, description')
        .order('item_name');
    final items = (data as List)
        .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('InventoryRepository → loaded ${items.length} items');
    return items;
  }

  /// Increments stock for multiple items atomically via a single RPC call.
  /// p_deltas = [{"inventory_id": "uuid", "delta": N}, ...]
  Future<void> incrementStockBulk(Map<String, int> deltas) async {
    if (deltas.isEmpty) return;
    logger.d('InventoryRepository → incrementStockBulk: ${deltas.length} items');
    final payload = deltas.entries
        .map((e) => {'inventory_id': e.key, 'delta': e.value})
        .toList();
    await _supabase.rpc('increment_inventory_bulk', params: {'p_deltas': payload});
    logger.i('InventoryRepository → incrementStockBulk done');
  }
}
