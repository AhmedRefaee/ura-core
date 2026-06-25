import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../data/admin_repository.dart';

import '../../../core/logic/safe_emit.dart';

class AdminState extends Equatable {
  final bool loading;
  final List<AdminOrg> orgs;
  final String? error;

  const AdminState({this.loading = false, this.orgs = const [], this.error});

  AdminState copyWith({bool? loading, List<AdminOrg>? orgs, String? error}) =>
      AdminState(
        loading: loading ?? this.loading,
        orgs: orgs ?? this.orgs,
        error: error,
      );

  @override
  List<Object?> get props => [loading, orgs, error];
}

class AdminCubit extends Cubit<AdminState> with SafeEmit<AdminState> {
  final AdminRepository _repo;

  AdminCubit(this._repo) : super(const AdminState());

  Future<void> load() async {
    safeEmit(state.copyWith(loading: true, error: null));
    final result = await _repo.listOrgs();
    switch (result) {
      case AppSuccess(:final data):
        safeEmit(state.copyWith(loading: false, orgs: data));
      case AppFailure(:final error):
        safeEmit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<AppResult<List<AdminMember>>> members(String orgId) =>
      _repo.listMembers(orgId);

  Future<void> toggleDiscoverable(String orgId, bool value) async {
    await _repo.setDiscoverable(orgId, value);
    await load();
  }

  Future<void> rotateJoinCode(String orgId) async {
    await _repo.rotateJoinCode(orgId);
    await load();
  }

  Future<AppResult<void>> approveUser(String userId, String role) =>
      _repo.approveUser(userId, role);
}
