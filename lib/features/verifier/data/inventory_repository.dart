import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';

class InventoryRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AppResult<List<InventoryItem>>> fetchInventory() async {
    try {
      logger.d('InventoryRepository → fetchInventory');
      final data = await _supabase
          .from('inventory')
          .select('id, item_name, sku, quantity, unit, category, min_quantity, description')
          .order('item_name');
      final items = (data as List)
          .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('InventoryRepository → loaded ${items.length} items');
      return AppSuccess(items);
    } catch (e, st) {
      logger.e('InventoryRepository → fetchInventory failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Map<String, InventoryItem>>> fetchItemsByIds(List<String> ids) async {
    if (ids.isEmpty) return const AppSuccess({});
    try {
      logger.d('InventoryRepository → fetchItemsByIds: ${ids.length} ids');
      final data = await _supabase
          .from('inventory')
          .select('id, item_name, sku, quantity, unit, category, min_quantity, description')
          .inFilter('id', ids);
      final map = {
        for (final row in (data as List))
          row['id'] as String: InventoryItem.fromMap(row as Map<String, dynamic>)
      };
      return AppSuccess(map);
    } catch (e, st) {
      logger.e('InventoryRepository → fetchItemsByIds failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> incrementStockBulk(Map<String, int> deltas) async {
    if (deltas.isEmpty) return const AppSuccess(null);
    try {
      logger.d('InventoryRepository → incrementStockBulk: ${deltas.length} items');
      final payload = deltas.entries
          .map((e) => {'inventory_id': e.key, 'delta': e.value})
          .toList();
      await _supabase.rpc('increment_inventory_bulk', params: {'p_deltas': payload});
      logger.i('InventoryRepository → incrementStockBulk done');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('InventoryRepository → incrementStockBulk failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
