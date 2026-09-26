import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../projects/data/project_repository.dart';
import '../../verifier/data/entity_repository.dart';
import '../data/delivery_receipt_repository.dart';
import '../data/delivery_receipt_storage_service.dart';
import 'delivery_receipt_pdf.dart';
import '../../../core/storage/signed_storage_url.dart';

part 'create_delivery_receipt_state.dart';

/// Where the flow was opened from. Launched after an order's last step it
/// arrives with the entity (and the project, if the order has one) already
/// known; launched standalone it arrives with nothing.
class DeliveryReceiptLaunch {
  final String? orderId;
  final Entity? entity;
  final String? projectId;

  /// Editing: the سند being replaced. Its entity, project, quantities and
  /// note are pre-filled; filing archives it in the same transaction.
  final DeliveryReceipt? replacing;

  const DeliveryReceiptLaunch({this.orderId, this.entity, this.projectId, this.replacing});

  DeliveryReceiptLaunch.edit(DeliveryReceipt receipt)
      : orderId = receipt.orderId,
        entity = receipt.entity,
        projectId = receipt.projectId,
        replacing = receipt;

  bool get isEdit => replacing != null;
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
    final (entities, withProjects) = await (
      _entities.fetchEntities(),
      _projects.fetchEntityIdsWithProjects(),
    ).wait;
    switch (entities) {
      case AppSuccess(:final data):
        emit(state.copyWith(
          loading: false,
          entities: data,
          entityIdsWithProjects: withProjects is AppSuccess<Set<String>> ? withProjects.data : null,
        ));
      case AppFailure(:final error):
        emit(state.copyWith(loading: false, error: error.message));
        return;
    }
    final entity = launch.entity;
    if (entity != null) await selectEntity(entity, preselectProjectId: launch.projectId);
  }

  /// Back to the entity step.
  void clearEntity() {
    _entityToken++;
    _projectToken++;
    emit(CreateDeliveryReceiptState(
      entities: state.entities,
      entityIdsWithProjects: state.entityIdsWithProjects,
    ));
  }

  /// Back to the project step, keeping the entity and its projects.
  void clearProject() {
    _projectToken++;
    emit(CreateDeliveryReceiptState(
      entities: state.entities,
      entityIdsWithProjects: state.entityIdsWithProjects,
      entity: state.entity,
      projects: state.projects,
    ));
  }

  // Picking A then quickly B must not let A's slower response land on top of
  // B. Each pick takes a new token; responses for an older token are dropped.
  int _entityToken = 0;
  int _projectToken = 0;

  Future<void> selectEntity(Entity entity, {String? preselectProjectId}) async {
    final token = ++_entityToken;
    _projectToken++;
    emit(CreateDeliveryReceiptState(
      entities: state.entities,
      entityIdsWithProjects: state.entityIdsWithProjects,
      entity: entity,
      loading: true,
    ));
    final result = await _projects.fetchProjectsForEntity(entity.id);
    if (token != _entityToken) return;
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
    final token = ++_projectToken;
    emit(state.copyWith(
      project: project,
      items: const [],
      quantities: const {},
      invalid: const {},
      loading: true,
      clearError: true,
    ));
    final result = await _projects.fetchProjectItems(project.id);
    if (token != _projectToken) return;
    switch (result) {
      case AppSuccess(:final data):
        emit(state.copyWith(loading: false, items: data));
        _prefillFromReplaced(project, data);
      case AppFailure(:final error):
        emit(state.copyWith(loading: false, error: error.message));
    }
  }

  bool _prefilled = false;

  /// Editing: carry the old سند's quantities over, once, onto the lines that
  /// still exist in the (possibly re-imported) quotation.
  void _prefillFromReplaced(Project project, List<ProjectItem> items) {
    final old = launch.replacing;
    if (old == null || _prefilled || project.id != old.projectId) return;
    _prefilled = true;
    final present = {for (final i in items) i.id};
    final quantities = <String, double>{
      for (final line in old.items)
        if (line.projectItemId != null && present.contains(line.projectItemId)) line.projectItemId!: line.quantityDelivered,
    };
    emit(state.copyWith(quantities: quantities, droppedFromOriginal: old.items.length - quantities.length));
  }

  /// Quantity exactly as typed. Empty clears the line; anything that isn't a
  /// number marks the row invalid (and blocks submit) instead of becoming 0.
  void setQuantityText(String projectItemId, String raw) {
    final invalid = Map<String, String>.from(state.invalid);
    final parsed = parseLocalizedNumber(raw);
    if (raw.trim().isNotEmpty && (parsed == null || parsed < 0)) {
      invalid[projectItemId] = raw;
      emit(state.copyWith(invalid: invalid));
      return;
    }
    invalid.remove(projectItemId);
    emit(state.copyWith(invalid: invalid));
    setQuantity(projectItemId, parsed ?? 0);
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
        clientLogoBytes: await _fetchLetterhead(project.letterheadImageUrl),
        notes: notes,
        lines: [
          for (final i in chosen)
            ReceiptPdfLine(
              itemName: i.itemName,
              description: packagingOf(i.description),
              unit: i.unit,
              quantity: state.quantities[i.id]!,
            ),
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
        replacesReceiptId: launch.replacing?.id,
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
  Future<Uint8List?> _fetchLetterhead(String? stored) async {
    final url = await SignedStorageUrl.resolve('project-letterheads', stored);
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
