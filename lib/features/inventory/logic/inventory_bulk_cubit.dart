import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/inventory_management_repository.dart';

// ── States ──────────────────────────────────────────────────────────────────

abstract class InventoryBulkState extends Equatable {
  const InventoryBulkState();
  @override
  List<Object?> get props => [];
}

class InventoryBulkInitial extends InventoryBulkState {}

class InventoryBulkLoading extends InventoryBulkState {}

class InventoryBulkReady extends InventoryBulkState {
  final List<InventoryItem> items;
  final Map<String, int> pendingQuantities;

  const InventoryBulkReady({
    required this.items,
    this.pendingQuantities = const {},
  });

  bool get hasChanges => pendingQuantities.isNotEmpty;

  List<InventoryItem> get changedItems =>
      items.where((i) => pendingQuantities.containsKey(i.id)).toList();

  int effectiveQuantity(InventoryItem item) =>
      pendingQuantities[item.id] ?? item.quantity;

  InventoryBulkReady copyWith({
    List<InventoryItem>? items,
    Map<String, int>? pendingQuantities,
  }) {
    return InventoryBulkReady(
      items: items ?? this.items,
      pendingQuantities: pendingQuantities ?? this.pendingQuantities,
    );
  }

  @override
  List<Object?> get props => [items, pendingQuantities];
}

class InventoryBulkSaving extends InventoryBulkState {}

class InventoryBulkSuccess extends InventoryBulkState {}

class InventoryBulkError extends InventoryBulkState {
  final String message;
  const InventoryBulkError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class InventoryBulkCubit extends Cubit<InventoryBulkState> {
  final InventoryManagementRepository _repo;

  InventoryBulkCubit(this._repo) : super(InventoryBulkInitial());

  Future<void> loadItems() async {
    emit(InventoryBulkLoading());
    final result = await _repo.fetchInventory();
    switch (result) {
      case AppSuccess(:final data):
        logger.d('InventoryBulkCubit loaded ${data.length} items');
        emit(InventoryBulkReady(items: data));
      case AppFailure(:final error):
        logger.e('InventoryBulkCubit load failed: ${error.message}');
        emit(InventoryBulkError(error.message));
    }
  }

  void setQuantity(String itemId, int quantity) {
    final current = state;
    if (current is! InventoryBulkReady) return;
    final updated = Map<String, int>.from(current.pendingQuantities);
    final originalItem = current.items.firstWhere((i) => i.id == itemId);
    if (quantity == originalItem.quantity) {
      updated.remove(itemId);
    } else {
      updated[itemId] = quantity;
    }
    emit(current.copyWith(pendingQuantities: updated));
  }

  void resetItem(String itemId) {
    final current = state;
    if (current is! InventoryBulkReady) return;
    final updated = Map<String, int>.from(current.pendingQuantities)..remove(itemId);
    emit(current.copyWith(pendingQuantities: updated));
  }

  Future<void> saveChanges() async {
    final current = state;
    if (current is! InventoryBulkReady || !current.hasChanges) return;
    emit(InventoryBulkSaving());
    final updates = current.pendingQuantities.entries
        .map((e) => (itemId: e.key, quantity: e.value))
        .toList();
    final result = await _repo.bulkUpdateQuantities(updates);
    switch (result) {
      case AppSuccess():
        logger.i('InventoryBulkCubit saved ${updates.length} changes');
        emit(InventoryBulkSuccess());
      case AppFailure(:final error):
        logger.e('InventoryBulkCubit save failed: ${error.message}');
        emit(InventoryBulkError(error.message));
    }
  }
}
