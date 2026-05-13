import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/draft_order_item.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_template.dart';

class OrderTemplateRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _select = '*, order_template_items(*)';

  Future<AppResult<List<OrderTemplate>>> fetchForEntity(String entityId) async {
    try {
      logger.d('OrderTemplateRepository → fetchForEntity $entityId');
      final data = await _supabase
          .from('order_templates')
          .select(_select)
          .eq('entity_id', entityId)
          .or('is_manual.eq.true,usage_count.gte.3')
          .order('usage_count', ascending: false);
      final templates = (data as List)
          .map((e) => OrderTemplate.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('OrderTemplateRepository → loaded ${templates.length} templates');
      return AppSuccess(templates);
    } catch (e, st) {
      logger.e('OrderTemplateRepository → fetchForEntity failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> trackUsage({
    required String entityId,
    required OrderDirection direction,
    required String? repId,
    required String? notes,
    required List<DraftOrderItem> items,
  }) async {
    try {
      logger.d('OrderTemplateRepository → trackUsage');
      final fp = _fingerprint(direction, items);
      final existing = await _supabase
          .from('order_templates')
          .select('id')
          .eq('entity_id', entityId)
          .eq('fingerprint', fp)
          .maybeSingle();

      if (existing != null) {
        await _supabase.rpc(
          'increment_template_usage',
          params: {'p_id': existing['id']},
        );
        logger.i('OrderTemplateRepository → incremented usage for ${existing['id']}');
      } else {
        await _insertTemplate(
          entityId: entityId,
          direction: direction,
          repId: repId,
          notes: notes,
          items: items,
          isManual: false,
          fingerprint: fp,
        );
        logger.i('OrderTemplateRepository → created new auto-template');
      }
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('OrderTemplateRepository → trackUsage failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> saveManual({
    required String entityId,
    required OrderDirection direction,
    required String? repId,
    required String? notes,
    required List<DraftOrderItem> items,
  }) async {
    try {
      logger.d('OrderTemplateRepository → saveManual');
      final fp = _fingerprint(direction, items);
      final existing = await _supabase
          .from('order_templates')
          .select('id')
          .eq('entity_id', entityId)
          .eq('fingerprint', fp)
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('order_templates')
            .update({'is_manual': true, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', existing['id'] as String);
        logger.i('OrderTemplateRepository → marked existing template as manual');
      } else {
        await _insertTemplate(
          entityId: entityId,
          direction: direction,
          repId: repId,
          notes: notes,
          items: items,
          isManual: true,
          fingerprint: fp,
        );
        logger.i('OrderTemplateRepository → created new manual template');
      }
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('OrderTemplateRepository → saveManual failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteTemplate(String id) async {
    try {
      logger.d('OrderTemplateRepository → deleteTemplate $id');
      await _supabase.from('order_templates').delete().eq('id', id);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('OrderTemplateRepository → deleteTemplate failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _fingerprint(OrderDirection direction, List<DraftOrderItem> items) {
    final sorted = [...items]
      ..sort((a, b) => (a.inventoryId ?? a.customDescription ?? '')
          .compareTo(b.inventoryId ?? b.customDescription ?? ''));
    return jsonEncode({
      'dir': _directionToString(direction),
      'items': sorted
          .map((i) => {
                'inv': i.inventoryId,
                'desc': i.customDescription,
                'qty': i.quantity,
              })
          .toList(),
    });
  }

  String _directionToString(OrderDirection d) {
    switch (d) {
      case OrderDirection.inboundRep:
        return 'inbound_rep';
      case OrderDirection.inboundExternal:
        return 'inbound_external';
      default:
        return 'outbound';
    }
  }

  Future<void> _insertTemplate({
    required String entityId,
    required OrderDirection direction,
    required String? repId,
    required String? notes,
    required List<DraftOrderItem> items,
    required bool isManual,
    required String fingerprint,
  }) async {
    final row = await _supabase
        .from('order_templates')
        .insert({
          'entity_id': entityId,
          'direction': _directionToString(direction),
          'rep_id': repId,
          'notes': notes,
          'is_manual': isManual,
          'fingerprint': fingerprint,
          'created_by': _supabase.auth.currentUser?.id,
        })
        .select('id')
        .single();

    if (items.isEmpty) return;

    await _supabase.from('order_template_items').insert(
          items
              .map((i) => {
                    'template_id': row['id'] as String,
                    if (i.inventoryId != null) 'inventory_id': i.inventoryId,
                    if (i.inventoryName != null) 'inventory_name': i.inventoryName,
                    'quantity': i.quantity,
                    'is_custom': i.isCustom,
                    if (i.customDescription != null)
                      'custom_description': i.customDescription,
                    if (i.sourceInventoryId != null)
                      'source_inventory_id': i.sourceInventoryId,
                  })
              .toList(),
        );
  }
}
