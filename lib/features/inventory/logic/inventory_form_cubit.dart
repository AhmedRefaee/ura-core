import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/inventory_management_repository.dart';

// ── States ──────────────────────────────────────────────────────────────────

abstract class InventoryFormState extends Equatable {
  const InventoryFormState();
  @override
  List<Object?> get props => [];
}

class InventoryFormIdle extends InventoryFormState {}

class InventoryFormSaving extends InventoryFormState {}

class InventoryFormSuccess extends InventoryFormState {}

class InventoryFormError extends InventoryFormState {
  final String message;
  const InventoryFormError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class InventoryFormCubit extends Cubit<InventoryFormState> {
  final InventoryManagementRepository _repo;
  final InventoryItem? initialItem;

  bool get isEditing => initialItem != null;

  InventoryFormCubit(this._repo, {this.initialItem}) : super(InventoryFormIdle());

  Future<void> submit({
    required String name,
    required String unit,
    required int quantity,
    String? sku,
    String? category,
    int minQuantity = 0,
    String? description,
    String? notes,
  }) async {
    emit(InventoryFormSaving());

    final AppResult<void> result;
    if (isEditing) {
      result = await _repo.updateItem(
        initialItem!.id,
        name: name,
        unit: unit,
        quantity: quantity,
        sku: sku,
        category: category,
        minQuantity: minQuantity,
        description: description,
        notes: notes,
      );
    } else {
      result = await _repo.createItem(
        name: name,
        unit: unit,
        quantity: quantity,
        sku: sku,
        category: category,
        minQuantity: minQuantity,
        description: description,
        notes: notes,
      );
    }

    switch (result) {
      case AppSuccess():
        logger.i('InventoryFormCubit ${isEditing ? "updated" : "created"}: $name');
        emit(InventoryFormSuccess());
      case AppFailure(:final error):
        logger.e('InventoryFormCubit submit failed: ${error.message}');
        emit(InventoryFormError(error.message));
    }
  }
}
