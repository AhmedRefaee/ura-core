import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/entity.dart';

class EntityRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AppResult<List<Entity>>> fetchEntities({List<EntityCategory>? categories}) async {
    try {
      logger.d('EntityRepository → fetchEntities | categories: $categories');
      var query = _supabase.from('entities').select('id, name, category, contact_name, contact_phone, address');
      if (categories != null && categories.isNotEmpty) {
        final filter = categories.map((c) => 'category.eq.${c.dbValue}').join(',');
        final data = await query.or(filter).order('name');
        final entities = (data as List).map((e) => Entity.fromMap(e as Map<String, dynamic>)).toList();
        logger.i('EntityRepository → loaded ${entities.length} entities (filtered)');
        return AppSuccess(entities);
      }
      final data = await query.order('name');
      final entities = (data as List).map((e) => Entity.fromMap(e as Map<String, dynamic>)).toList();
      logger.i('EntityRepository → loaded ${entities.length} entities');
      return AppSuccess(entities);
    } catch (e, st) {
      logger.e('EntityRepository → fetchEntities failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Entity>> createEntity({
    required String name,
    required EntityCategory category,
    String? contactName,
    String? contactPhone,
    String? address,
  }) async {
    try {
      logger.d('EntityRepository → createEntity | name: $name category: $category');
      final entity = Entity(
        id: '',
        name: name.trim(),
        category: category,
        contactName: contactName?.trim().isEmpty == true ? null : contactName?.trim(),
        contactPhone: contactPhone?.trim().isEmpty == true ? null : contactPhone?.trim(),
        address: address?.trim().isEmpty == true ? null : address?.trim(),
      );
      final data = await _supabase
          .from('entities')
          .insert(entity.toInsertMap())
          .select('id, name, category, contact_name, contact_phone, address')
          .single();
      logger.i('EntityRepository → entity created: ${data['id']}');
      return AppSuccess(Entity.fromMap(data));
    } catch (e, st) {
      logger.e('EntityRepository → createEntity failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Entity>> updateEntity({
    required String id,
    required String name,
    required EntityCategory category,
    String? contactName,
    String? contactPhone,
    String? address,
  }) async {
    try {
      logger.d('EntityRepository → updateEntity | id: $id');
      final entity = Entity(
        id: id,
        name: name.trim(),
        category: category,
        contactName: contactName?.trim().isEmpty == true ? null : contactName?.trim(),
        contactPhone: contactPhone?.trim().isEmpty == true ? null : contactPhone?.trim(),
        address: address?.trim().isEmpty == true ? null : address?.trim(),
      );
      final data = await _supabase
          .from('entities')
          .update(entity.toUpdateMap())
          .eq('id', id)
          .select('id, name, category, contact_name, contact_phone, address')
          .single();
      logger.i('EntityRepository → entity updated: $id');
      return AppSuccess(Entity.fromMap(data));
    } catch (e, st) {
      logger.e('EntityRepository → updateEntity failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteEntity(String id) async {
    try {
      logger.d('EntityRepository → deleteEntity | id: $id');
      await _supabase.from('entities').delete().eq('id', id);
      logger.i('EntityRepository → entity deleted: $id');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('EntityRepository → deleteEntity failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
