import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/entity.dart';

class EntityRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Entity>> fetchEntities({EntityType? type}) async {
    logger.d('EntityRepository → fetchEntities | type: $type');
    var query = _supabase.from('entities').select();
    if (type != null) {
      final typeStr = type == EntityType.customer ? 'customer' : 'supplier';
      final data = await query.eq('type', typeStr).order('name');
      final entities = (data as List).map((e) => Entity.fromMap(e as Map<String, dynamic>)).toList();
      logger.i('EntityRepository → loaded ${entities.length} entities (filtered: $typeStr)');
      return entities;
    }
    final data = await query.order('name');
    final entities = (data as List).map((e) => Entity.fromMap(e as Map<String, dynamic>)).toList();
    logger.i('EntityRepository → loaded ${entities.length} entities');
    return entities;
  }
}
