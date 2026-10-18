import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../models/shared_project.dart';

/// Where share links point. Fixed (not Uri.base) so a link made in the
/// Android app opens the website too. Hash routing -- see app_router.dart.
const kPublicWebOrigin = 'https://ura-core-9981c.web.app';

String shareLinkUrl(String token) => '$kPublicWebOrigin/#/share/$token';

/// Read-only project share links for outside entities -- see
/// 20261018120000_project_share_links.sql. Every write goes through an RPC
/// that checks the caller's role/org server-side.
class ProjectShareRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AppResult<List<ProjectShareLink>>> listLinks(String projectId) async {
    try {
      final data = await _supabase
          .from('project_share_links')
          .select('id, token, created_at, expires_at, revoked_at, can_submit')
          .eq('project_id', projectId)
          .order('created_at', ascending: false);
      return AppSuccess([
        for (final e in data as List) ProjectShareLink.fromMap(e as Map<String, dynamic>),
      ]);
    } catch (e, st) {
      logger.e('ProjectShareRepository → listLinks failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Returns the new link's token.
  Future<AppResult<String>> createLink(
    String projectId, {
    DateTime? expiresAt,
    bool canSubmit = false,
  }) async {
    try {
      logger.d('ProjectShareRepository → createLink: $projectId');
      final result = await _supabase.rpc('create_project_share_link', params: {
        'p_project_id': projectId,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_can_submit': canSubmit,
      });
      if (result['success'] as bool? ?? false) return AppSuccess(result['token'] as String);
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('ProjectShareRepository → createLink failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> revokeLink(String linkId) async {
    try {
      logger.d('ProjectShareRepository → revokeLink: $linkId');
      final result = await _supabase.rpc('revoke_project_share_link', params: {'p_link_id': linkId});
      if (result['success'] as bool? ?? false) return const AppSuccess(null);
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('ProjectShareRepository → revokeLink failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Files a سند for approval through the link. Returns the new receipt's id.
  /// [items] is [{project_item_id, quantity_delivered, notes?}].
  Future<AppResult<String>> submitReceipt({
    required String token,
    required String submitterName,
    String? submitterPhone,
    required List<Map<String, dynamic>> items,
    String? notes,
    required Map<String, dynamic> meta,
  }) async {
    try {
      logger.d('ProjectShareRepository → submitReceipt | items: ${items.length}');
      final result = await _supabase.rpc('submit_shared_receipt', params: {
        'p_token': token,
        'p_submitter_name': submitterName,
        'p_submitter_phone': submitterPhone,
        'p_items': items,
        'p_notes': notes,
        'p_meta': meta,
      });
      if (result['success'] as bool? ?? false) return AppSuccess(result['delivery_receipt_id'] as String);
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('ProjectShareRepository → submitReceipt failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// The سندات filed through this link, newest first -- and only those.
  Future<AppResult<List<SharedReceipt>>> fetchSharedReceipts(String token) async {
    try {
      final result = await _supabase.rpc('get_shared_receipts', params: {'p_token': token});
      return AppSuccess([
        for (final e in (result as List? ?? const [])) SharedReceipt.fromMap(e as Map<String, dynamic>),
      ]);
    } catch (e, st) {
      logger.e('ProjectShareRepository → fetchSharedReceipts failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Works signed out. Null data = the link is unknown, revoked or expired.
  Future<AppResult<SharedProject?>> fetchShared(String token) async {
    try {
      final result = await _supabase.rpc('get_shared_project', params: {'p_token': token});
      if (result == null) return const AppSuccess(null);
      return AppSuccess(SharedProject.fromMap(result as Map<String, dynamic>));
    } catch (e, st) {
      logger.e('ProjectShareRepository → fetchShared failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
