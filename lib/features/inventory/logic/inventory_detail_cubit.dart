import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_audit_log_entry.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/inventory_management_repository.dart';

// ── States ──────────────────────────────────────────────────────────────────

abstract class InventoryDetailState extends Equatable {
  const InventoryDetailState();
  @override
  List<Object?> get props => [];
}

class InventoryDetailInitial extends InventoryDetailState {}

class InventoryDetailLoading extends InventoryDetailState {}

class InventoryDetailLoaded extends InventoryDetailState {
  final InventoryItem item;
  final List<InventoryAuditLogEntry> auditLog;
  final bool isActing;

  const InventoryDetailLoaded({
    required this.item,
    required this.auditLog,
    this.isActing = false,
  });

  InventoryDetailLoaded copyWith({
    InventoryItem? item,
    List<InventoryAuditLogEntry>? auditLog,
    bool? isActing,
  }) {
    return InventoryDetailLoaded(
      item: item ?? this.item,
      auditLog: auditLog ?? this.auditLog,
      isActing: isActing ?? this.isActing,
    );
  }

  @override
  List<Object?> get props => [item, auditLog, isActing];
}

class InventoryDetailError extends InventoryDetailState {
  final String message;
  const InventoryDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class InventoryDetailSuccess extends InventoryDetailState {
  final String message;
  const InventoryDetailSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class InventoryDetailCubit extends Cubit<InventoryDetailState> {
  final InventoryManagementRepository _repo;
  final String _itemId;

  InventoryDetailCubit(this._repo, this._itemId)
      : super(InventoryDetailInitial());

  Future<void> load() async {
    emit(InventoryDetailLoading());
    try {
      final results = await Future.wait([
        _repo.fetchItemDetail(_itemId),
        _repo.fetchAuditLog(_itemId),
      ]);
      logger.d('InventoryDetailCubit loaded item $_itemId');
      emit(InventoryDetailLoaded(
        item: results[0] as InventoryItem,
        auditLog: results[1] as List<InventoryAuditLogEntry>,
      ));
    } catch (e) {
      logger.e('InventoryDetailCubit load failed', error: e);
      emit(InventoryDetailError(e.toString()));
    }
  }

  Future<void> deleteItem() async {
    final current = state;
    if (current is! InventoryDetailLoaded) return;
    emit(current.copyWith(isActing: true));
    try {
      await _repo.deleteItem(_itemId);
      logger.i('InventoryDetailCubit deleted item $_itemId');
      emit(const InventoryDetailSuccess('تم حذف العنصر بنجاح'));
    } catch (e) {
      logger.e('InventoryDetailCubit deleteItem failed', error: e);
      emit(current.copyWith(isActing: false));
      emit(InventoryDetailError(e.toString()));
    }
  }
}
