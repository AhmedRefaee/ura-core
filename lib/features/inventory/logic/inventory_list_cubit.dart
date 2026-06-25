import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/inventory_management_repository.dart';

import '../../../core/logic/safe_emit.dart';
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
      final matchesSearch =
          searchQuery.isEmpty ||
          item.itemName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (item.sku?.toLowerCase().contains(searchQuery.toLowerCase()) ??
              false);
      final matchesCategory =
          selectedCategory == null || item.category == selectedCategory;
      final matchesStatus =
          statusFilter == null || item.availabilityStatus == statusFilter;
      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();
  }

  List<String> get availableCategories {
    final cats =
        allItems.map((i) => i.category).whereType<String>().toSet().toList()
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
  List<Object?> get props => [
    allItems,
    searchQuery,
    selectedCategory,
    statusFilter,
  ];
}

const _sentinel = Object();

class InventoryListError extends InventoryListState {
  final String message;
  const InventoryListError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class InventoryListCubit extends Cubit<InventoryListState>
    with SafeEmit<InventoryListState> {
  final InventoryManagementRepository _repo;
  RealtimeChannel? _channel;

  InventoryListCubit(this._repo) : super(InventoryListInitial());

  Future<void> loadInventory() async {
    safeEmit(InventoryListLoading());
    await _fetchInventory();
  }

  Future<void> _fetchInventory() async {
    final result = await _repo.fetchInventory();
    if (isClosed) return;
    switch (result) {
      case AppSuccess(:final data):
        logger.d('InventoryListCubit loaded ${data.length} items');
        final current = state;
        safeEmit(
          InventoryListLoaded(allItems: data).copyWith(
            searchQuery: current is InventoryListLoaded
                ? current.searchQuery
                : '',
            selectedCategory: current is InventoryListLoaded
                ? current.selectedCategory
                : null,
            statusFilter: current is InventoryListLoaded
                ? current.statusFilter
                : null,
          ),
        );
        _channel ??= Supabase.instance.client
            .channel('inventory-list-$hashCode')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'inventory_items',
              callback: (_) => _fetchInventory(),
            )
            .subscribe();
      case AppFailure(:final error):
        logger.e('InventoryListCubit load failed: ${error.message}');
        if (!isClosed) safeEmit(InventoryListError(error.message));
    }
  }

  @override
  Future<void> close() async {
    await _channel?.unsubscribe();
    return super.close();
  }

  void setSearch(String query) {
    final current = state;
    if (current is InventoryListLoaded) {
      safeEmit(current.copyWith(searchQuery: query));
    }
  }

  void setCategory(String? category) {
    final current = state;
    if (current is InventoryListLoaded) {
      safeEmit(current.copyWith(selectedCategory: category));
    }
  }

  void setStatusFilter(AvailabilityStatus? status) {
    final current = state;
    if (current is InventoryListLoaded) {
      safeEmit(current.copyWith(statusFilter: status));
    }
  }

  Future<void> loadUsageCounts() async {
    final current = state;
    if (current is! InventoryListLoaded) return;
    final result = await _repo.fetchUsageCounts();
    if (isClosed) return;
    switch (result) {
      case AppSuccess(:final data):
        final updated = current.allItems
            .map((item) => item.copyWithUsageCount(data[item.id] ?? 0))
            .toList();
        safeEmit(current.copyWith(allItems: updated));
      case AppFailure(:final error):
        logger.w('loadUsageCounts failed (non-fatal): ${error.message}');
    }
  }
}
