import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../../projects/data/project_repository.dart';
import '../../verifier/data/entity_repository.dart';
import '../data/delivery_receipt_repository.dart';
import '../data/delivery_receipt_storage_service.dart';
import 'delivery_receipt_pdf.dart';

part 'create_delivery_receipt_state.dart';

/// Where the flow was opened from. Launched after an order's last step it
/// arrives with the entity (and the project, if the order has one) already
/// known; launched standalone it arrives with nothing.
class DeliveryReceiptLaunch {
  final String? orderId;
  final Entity? entity;
  final String? projectId;
  const DeliveryReceiptLaunch({this.orderId, this.entity, this.projectId});
}

class CreateDeliveryReceiptCubit extends Cubit<CreateDeliveryReceiptState> {
  final EntityRepository _entities;
  final ProjectRepository _projects;
  final DeliveryReceiptRepository _receipts;
  final DeliveryReceiptStorageService _storage;
  final DeliveryReceiptLaunch launch;

  CreateDeliveryReceiptCubit(
    this._entities,
    this._projects,
    this._receipts,
    this._storage,
    this.launch,
  ) : super(const CreateDeliveryReceiptState());

  Future<void> init() async {
    emit(state.copyWith(loading: true, clearError: true));
    final result = await _entities.fetchEntities();
    switch (result) {
      case AppSuccess(:final data):
        emit(state.copyWith(loading: false, entities: data));
      case AppFailure(:final error):
        emit(state.copyWith(loading: false, error: error.message));
        return;
    }
    final entity = launch.entity;
    if (entity != null) await selectEntity(entity, preselectProjectId: launch.projectId);
  }

  Future<void> selectEntity(Entity entity, {String? preselectProjectId}) async {
    emit(CreateDeliveryReceiptState(
      entities: state.entities,
      entity: entity,
      loading: true,
    ));
    final result = await _projects.fetchProjectsForEntity(entity.id);
    switch (result) {
      case AppSuccess(:final data):
        emit(state.copyWith(loading: false, projects: data));
        final match = data.where((p) => p.id == preselectProjectId).firstOrNull;
        if (match != null) {
          await selectProject(match);
        } else if (data.length == 1) {
          await selectProject(data.single);
        }
      case AppFailure(:final error):
        emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<void> selectProject(Project project) async {
    emit(state.copyWith(project: project, items: const [], quantities: const {}, loading: true, clearError: true));
    final result = await _projects.fetchProjectItems(project.id);
    switch (result) {
      case AppSuccess(:final data):
        emit(state.copyWith(loading: false, items: data));
      case AppFailure(:final error):
        emit(state.copyWith(loading: false, error: error.message));
    }
  }

  void setQuantity(String projectItemId, double quantity) {
    final next = Map<String, double>.from(state.quantities);
    if (quantity > 0) {
      next[projectItemId] = quantity;
    } else {
      next.remove(projectItemId);
    }
    emit(state.copyWith(quantities: next, clearError: true));
  }

  Future<void> submit({required String repName, String? notes}) async {
    final entity = state.entity;
    final project = state.project;
    if (entity == null || project == null || !state.canSubmit) return;
    emit(state.copyWith(submitting: true, clearError: true));

    final chosen = state.items.where((i) => (state.quantities[i.id] ?? 0) > 0).toList();

    try {
      final pdf = await DeliveryReceiptPdf.build(
        entityName: entity.name,
        projectName: project.name,
        repName: repName,
        date: DateTime.now(),
        letterheadBytes: await _fetchLetterhead(project.letterheadImageUrl),
        notes: notes,
        lines: [
          for (final i in chosen)
            ReceiptPdfLine(itemName: i.itemName, unit: i.unit, quantity: state.quantities[i.id]!),
        ],
      );

      final upload = await _storage.uploadPdf(pdf);
      final String pdfUrl;
      switch (upload) {
        case AppSuccess(:final data):
          pdfUrl = data;
        case AppFailure(:final error):
          emit(state.copyWith(submitting: false, error: error.message));
          return;
      }

      final created = await _receipts.createDeliveryReceipt(
        entityId: entity.id,
        projectId: project.id,
        orderId: launch.orderId,
        pdfUrl: pdfUrl,
        notes: (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
        items: [
          for (final i in chosen)
            {'project_item_id': i.id, 'quantity_delivered': state.quantities[i.id]},
        ],
      );
      switch (created) {
        case AppSuccess(:final data):
          emit(state.copyWith(submitting: false, pdfBytes: pdf, receiptId: data));
        case AppFailure(:final error):
          emit(state.copyWith(submitting: false, error: error.message));
      }
    } catch (e, st) {
      logger.e('CreateDeliveryReceiptCubit → submit failed', error: e, stackTrace: st);
      emit(state.copyWith(submitting: false, error: 'تعذر إنشاء السند، حاول مرة أخرى'));
    }
  }

  /// A missing or unreachable letterhead shouldn't block filing the سند --
  /// the PDF just goes out without a header image.
  Future<Uint8List?> _fetchLetterhead(String? url) async {
    if (url == null) return null;
    try {
      final res = await http.get(Uri.parse(url));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (e) {
      logger.w('CreateDeliveryReceiptCubit → letterhead fetch failed: $e');
      return null;
    }
  }
}
