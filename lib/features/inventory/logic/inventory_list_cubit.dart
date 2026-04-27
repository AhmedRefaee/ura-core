import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/inventory_management_repository.dart';

// ── States ──────────────────────────────────────────────────────────────────

abstract class InventoryListState extends Equatable {
  const InventoryListState();
  @override
  List<Object?> get props => [];
}

class InventoryListInitial extends InventoryListState {}

class InventoryListLoading extends InventoryListState {}

class InventoryListLoaded extends InventoryListState {
  final List<InventoryItem> allItems;
  final String searchQuery;
  final String? selectedCategory;
  final AvailabilityStatus? statusFilter;

  const InventoryListLoaded({
    required this.allItems,
    this.searchQuery = '',
    this.selectedCategory,
    this.statusFilter,
  });

  List<InventoryItem> get filteredItems {
    return allItems.where((item) {
      final matchesSearch = searchQuery.isEmpty ||
          item.itemName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (item.sku?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
      final matchesCategory =
          selectedCategory == null || item.category == selectedCategory;
      final matchesStatus =
          statusFilter == null || item.availabilityStatus == statusFilter;
      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();
  }

  List<String> get availableCategories {
    final cats = allItems
        .map((i) => i.category)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return cats;
  }

  InventoryListLoaded copyWith({
    List<InventoryItem>? allItems,
    String? searchQuery,
    Object? selectedCategory = _sentinel,
    Object? statusFilter = _sentinel,
  }) {
    return InventoryListLoaded(
      allItems: allItems ?? this.allItems,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory == _sentinel
          ? this.selectedCategory
          : selectedCategory as String?,
      statusFilter: statusFilter == _sentinel
          ? this.statusFilter
          : statusFilter as AvailabilityStatus?,
    );
  }

  @override
  List<Object?> get props =>
      [allItems, searchQuery, selectedCategory, statusFilter];
}

// Sentinel for nullable copyWith fields
const _sentinel = Object();

class InventoryListError extends InventoryListState {
  final String message;
  const InventoryListError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class InventoryListCubit extends Cubit<InventoryListState> {
  final InventoryManagementRepository _repo;

  InventoryListCubit(this._repo) : super(InventoryListInitial());

  Future<void> loadInventory() async {
    emit(InventoryListLoading());
    try {
      final items = await _repo.fetchInventory();
      logger.d('InventoryListCubit loaded ${items.length} items');
      emit(InventoryListLoaded(allItems: items));
    } catch (e) {
      logger.e('InventoryListCubit load failed', error: e);
      emit(InventoryListError(e.toString()));
    }
  }

  void setSearch(String query) {
    final current = state;
    if (current is InventoryListLoaded) {
      emit(current.copyWith(searchQuery: query));
    }
  }

  void setCategory(String? category) {
    final current = state;
    if (current is InventoryListLoaded) {
      emit(current.copyWith(selectedCategory: category));
    }
  }

  void setStatusFilter(AvailabilityStatus? status) {
    final current = state;
    if (current is InventoryListLoaded) {
      emit(current.copyWith(statusFilter: status));
    }
  }
}
