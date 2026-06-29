import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';

typedef AdminOrg = ({
  String id,
  String name,
  String joinCode,
  bool isDiscoverable,
  int memberCount,
  int pendingCount,
});

typedef AdminMember = ({
  String id,
  String fullName,
  String? phone,
  String? role,
  bool isApproved,
});

/// Cross-org data access for the hidden platform admin. All reads rely on the
/// is_platform_admin() RLS bypass; mutations go through SECURITY DEFINER RPCs.
class AdminRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AppResult<List<AdminOrg>>> listOrgs() async {
    try {
      final rows = (await _supabase.rpc('admin_list_orgs') as List?) ?? const [];
      final orgs = rows
          .map<AdminOrg>((r) => (
                id: r['id'] as String,
                name: r['name'] as String,
                joinCode: r['join_code'] as String,
                isDiscoverable: r['is_discoverable'] as bool? ?? false,
                memberCount: (r['member_count'] as num?)?.toInt() ?? 0,
                pendingCount: (r['pending_count'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      return AppSuccess(orgs);
    } catch (e, st) {
      logger.e('admin listOrgs failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<AdminMember>>> listMembers(String orgId) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved')
          .eq('organization_id', orgId)
          .order('is_approved', ascending: true);
      final members = (rows as List)
          .map<AdminMember>((r) => (
                id: r['id'] as String,
                fullName: r['full_name'] as String,
                phone: r['phone'] as String?,
                role: r['role'] as String?,
                isApproved: r['is_approved'] as bool? ?? false,
              ))
          .toList();
      return AppSuccess(members);
    } catch (e, st) {
      logger.e('admin listMembers failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> setDiscoverable(String orgId, bool value) =>
      _rpc('admin_set_discoverable', {'p_org_id': orgId, 'p_value': value});

  Future<AppResult<void>> rotateJoinCode(String orgId) =>
      _rpc('admin_rotate_join_code', {'p_org_id': orgId});

  Future<AppResult<void>> approveUser(String userId, String role) =>
      _rpc('approve_user', {'target_user_id': userId, 'assigned_role': role});

  Future<AppResult<void>> changeMemberRole(String userId, String newRole) =>
      _rpc('admin_change_member_role', {
        'p_user_id': userId,
        'p_new_role': newRole,
      });

  Future<AppResult<void>> removeMember(String userId) =>
      _rpc('admin_remove_member', {'p_user_id': userId});

  Future<AppResult<void>> deleteOrganization(String orgId) =>
      _rpc('admin_delete_organization', {'p_org_id': orgId});

  Future<AppResult<void>> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      final result = await _supabase.rpc(fn, params: params);
      final map = result is Map ? result : <String, dynamic>{};
      if (map['success'] == true) return const AppSuccess(null);
      return AppFailure(ErrorHandler.fromRpcResult(map));
    } catch (e, st) {
      logger.e('admin $fn failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
