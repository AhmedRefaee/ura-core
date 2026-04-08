import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';

class InventoryRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<InventoryItem>> fetchInventory() async {
    logger.d('InventoryRepository → fetchInventory');
    final data = await _supabase
        .from('inventory')
        .select('id, item_name, sku, quantity, unit')
        .order('item_name');
    final items = (data as List)
        .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('InventoryRepository → loaded ${items.length} items');
    return items;
  }
}
