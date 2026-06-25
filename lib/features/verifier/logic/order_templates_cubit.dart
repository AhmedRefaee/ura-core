import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/order_template.dart';
import '../data/order_template_repository.dart';

import '../../../core/logic/safe_emit.dart';
// ── States ────────────────────────────────────────────────────────────────────

abstract class OrderTemplatesState extends Equatable {
  const OrderTemplatesState();
  @override
  List<Object?> get props => [];
}

class OrderTemplatesInitial extends OrderTemplatesState {}

class OrderTemplatesLoading extends OrderTemplatesState {}

class OrderTemplatesLoaded extends OrderTemplatesState {
  final List<OrderTemplate> templates;
  const OrderTemplatesLoaded(this.templates);
  @override
  List<Object?> get props => [templates];
}

class OrderTemplatesError extends OrderTemplatesState {
  final String message;
  const OrderTemplatesError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class OrderTemplatesCubit extends Cubit<OrderTemplatesState>
    with SafeEmit<OrderTemplatesState> {
  final OrderTemplateRepository _repo;

  OrderTemplatesCubit(this._repo) : super(OrderTemplatesInitial());

  Future<void> load(String entityId) async {
    if (isClosed) return;
    logger.d('OrderTemplatesCubit → load $entityId');
    safeEmit(OrderTemplatesLoading());
    final result = await _repo.fetchForEntity(entityId);
    if (isClosed) return;
    switch (result) {
      case AppSuccess(:final data):
        safeEmit(OrderTemplatesLoaded(data));
      case AppFailure(:final error):
        logger.e('OrderTemplatesCubit → load failed: ${error.message}');
        safeEmit(OrderTemplatesError(error.message));
    }
  }

  Future<void> delete(String templateId) async {
    final s = state;
    if (s is! OrderTemplatesLoaded) return;
    final optimistic = s.templates.where((t) => t.id != templateId).toList();
    safeEmit(OrderTemplatesLoaded(optimistic));
    final result = await _repo.deleteTemplate(templateId);
    if (isClosed) return;
    switch (result) {
      case AppSuccess():
        logger.i('OrderTemplatesCubit → deleted $templateId');
      case AppFailure(:final error):
        logger.e('OrderTemplatesCubit → delete failed: ${error.message}');
        safeEmit(s); // restore original list on failure
    }
  }
}
