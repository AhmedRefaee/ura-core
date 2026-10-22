import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';

class ProjectRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AppResult<List<Project>>> fetchProjectsForEntity(String entityId) async {
    try {
      logger.d('ProjectRepository → fetchProjectsForEntity: $entityId');
      final data = await _supabase
          .from('projects')
          .select()
          .eq('entity_id', entityId)
          .order('created_at', ascending: false);
      final projects = (data as List).map((e) => Project.fromMap(e as Map<String, dynamic>)).toList();
      logger.i('ProjectRepository → ${projects.length} projects loaded for entity $entityId');
      return AppSuccess(projects);
    } catch (e, st) {
      logger.e('ProjectRepository → fetchProjectsForEntity failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Which entities have at least one project -- a سند needs a project, so
  /// the rep's entity step lists only these. [onlyProjectIds] narrows it to
  /// projects the user may file for. Two narrow columns, one query.
  Future<AppResult<Set<String>>> fetchEntityIdsWithProjects({Set<String>? onlyProjectIds}) async {
    try {
      final data = await _supabase.from('projects').select('id, entity_id');
      return AppSuccess({
        for (final r in data as List)
          if (onlyProjectIds == null || onlyProjectIds.contains(r['id'])) r['entity_id'] as String,
      });
    } catch (e, st) {
      logger.e('ProjectRepository → fetchEntityIdsWithProjects failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Projects the signed-in user may file a سند for: every project for a
  /// verifier/admin, only assigned ones for a rep. The server's
  /// `can_file_receipt_for_project()` decides, so the picker matches what
  /// create_delivery_receipt will accept.
  Future<AppResult<Set<String>>> fetchReceiptProjectIds() async {
    try {
      final data = await _supabase.rpc('get_receipt_project_ids');
      return AppSuccess({for (final id in data as List) id as String});
    } catch (e, st) {
      logger.e('ProjectRepository → fetchReceiptProjectIds failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// The reps assigned to file سندات for [projectId].
  Future<AppResult<Set<String>>> fetchReceiptAssignees(String projectId) async {
    try {
      final data = await _supabase.from('project_receipt_assignees').select('user_id').eq('project_id', projectId);
      return AppSuccess({for (final r in data as List) r['user_id'] as String});
    } catch (e, st) {
      logger.e('ProjectRepository → fetchReceiptAssignees failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> setReceiptAssignee(String projectId, String userId, {required bool assigned}) async {
    try {
      logger.d('ProjectRepository → setReceiptAssignee | $projectId $userId $assigned');
      final result = await _supabase.rpc(
        assigned ? 'assign_project_receipt_user' : 'unassign_project_receipt_user',
        params: {'p_project_id': projectId, 'p_user_id': userId},
      );
      if (result['success'] as bool? ?? false) return const AppSuccess(null);
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('ProjectRepository → setReceiptAssignee failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Project>> createProject({
    required String entityId,
    required String name,
    String? letterheadImageUrl,
  }) async {
    try {
      logger.d('ProjectRepository → createProject | entityId: $entityId name: $name');
      final project = Project(
        id: '',
        entityId: entityId,
        name: name.trim(),
        letterheadImageUrl: letterheadImageUrl,
      );
      final data = await _supabase.from('projects').insert(project.toInsertMap()).select().single();
      logger.i('ProjectRepository → project created: ${data['id']}');
      return AppSuccess(Project.fromMap(data));
    } catch (e, st) {
      logger.e('ProjectRepository → createProject failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Project>> updateProject({
    required String id,
    String? name,
    String? letterheadImageUrl,
    // Distinguishes "don't touch the letterhead" (letterheadImageUrl left
    // null, the ?-prefixed map entry below omits the key entirely) from
    // "clear it" (this flag forces the key in with an explicit null value).
    bool clearLetterhead = false,
  }) async {
    try {
      logger.d('ProjectRepository → updateProject | id: $id');
      final data = await _supabase
          .from('projects')
          .update({
            if (name != null) 'name': name.trim(),
            if (clearLetterhead) 'letterhead_image_url': null else 'letterhead_image_url': ?letterheadImageUrl,
          })
          .eq('id', id)
          .select()
          .single();
      logger.i('ProjectRepository → project updated: $id');
      return AppSuccess(Project.fromMap(data));
    } catch (e, st) {
      logger.e('ProjectRepository → updateProject failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Deletes a project along with its بنود, share links and rep assignments
  /// (all ON DELETE CASCADE). A project any سند or order points at can't be
  /// deleted -- those foreign keys have no cascade on purpose.
  Future<AppResult<void>> deleteProject(String id) async {
    try {
      logger.d('ProjectRepository → deleteProject | id: $id');
      // RLS turns a forbidden delete into "0 rows", not an error.
      final deleted = await _supabase.from('projects').delete().eq('id', id).select('id');
      if ((deleted as List).isEmpty) {
        return const AppFailure(AppError(message: 'غير مصرح بحذف هذا المشروع', type: AppErrorType.permission));
      }
      logger.i('ProjectRepository → project deleted: $id');
      return const AppSuccess(null);
    } on PostgrestException catch (e, st) {
      if (e.code == '23503') {
        return const AppFailure(AppError(
          message: 'لا يمكن حذف المشروع لأن عليه سندات أو طلبات',
          type: AppErrorType.validation,
        ));
      }
      logger.e('ProjectRepository → deleteProject failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    } catch (e, st) {
      logger.e('ProjectRepository → deleteProject failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Reads through the `get_project_items` RPC rather than the base table --
  /// the table's own RLS hides rows entirely from non-commercial roles (see
  /// `project_item_pricing_visible()`), this is the one path every role uses.
  Future<AppResult<List<ProjectItem>>> fetchProjectItems(String projectId) async {
    try {
      logger.d('ProjectRepository → fetchProjectItems: $projectId');
      final data = await _supabase.rpc('get_project_items', params: {'p_project_id': projectId});
      final items = (data as List).map((e) => ProjectItem.fromMap(e as Map<String, dynamic>)).toList();
      logger.i('ProjectRepository → ${items.length} project items loaded for $projectId');
      return AppSuccess(items);
    } catch (e, st) {
      logger.e('ProjectRepository → fetchProjectItems failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Asks the server rather than checking the role locally, so who may see
  /// and edit quotation pricing stays defined in exactly one place:
  /// `project_item_pricing_visible()`.
  Future<AppResult<bool>> canEditPricing() async {
    try {
      final result = await _supabase.rpc('project_item_pricing_visible');
      return AppSuccess(result as bool? ?? false);
    } catch (e, st) {
      logger.e('ProjectRepository → canEditPricing failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<ProjectItem>> createProjectItem(ProjectItem item) async {
    try {
      logger.d('ProjectRepository → createProjectItem | projectId: ${item.projectId}');
      final data = await _supabase.from('project_items').insert(item.toInsertMap()).select().single();
      logger.i('ProjectRepository → project item created: ${data['id']}');
      return AppSuccess(ProjectItem.fromMap(data));
    } catch (e, st) {
      logger.e('ProjectRepository → createProjectItem failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<ProjectItem>> updateProjectItem(ProjectItem item) async {
    try {
      logger.d('ProjectRepository → updateProjectItem | id: ${item.id}');
      final data =
          await _supabase.from('project_items').update(item.toUpdateMap()).eq('id', item.id).select().single();
      logger.i('ProjectRepository → project item updated: ${item.id}');
      return AppSuccess(ProjectItem.fromMap(data));
    } catch (e, st) {
      logger.e('ProjectRepository → updateProjectItem failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Replaces every line of the project's quotation in one transaction (Excel
  /// import). Order in [items] becomes sort_order.
  Future<AppResult<int>> replaceProjectItems(String projectId, List<ProjectItem> items) async {
    try {
      logger.d('ProjectRepository → replaceProjectItems | $projectId: ${items.length} items');
      final result = await _supabase.rpc('replace_project_items', params: {
        'p_project_id': projectId,
        'p_items': [for (final i in items) i.toReplaceJson()],
      });
      if (result['success'] as bool? ?? false) {
        final count = (result['count'] as num?)?.toInt() ?? items.length;
        logger.i('ProjectRepository → replaced project items: $count');
        return AppSuccess(count);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('ProjectRepository → replaceProjectItems failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteProjectItem(String id) async {
    try {
      logger.d('ProjectRepository → deleteProjectItem | id: $id');
      await _supabase.from('project_items').delete().eq('id', id);
      logger.i('ProjectRepository → project item deleted: $id');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ProjectRepository → deleteProjectItem failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
