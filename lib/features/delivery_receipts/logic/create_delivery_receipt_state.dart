part of 'create_delivery_receipt_cubit.dart';

class CreateDeliveryReceiptState extends Equatable {
  final bool loading;
  final List<Entity> entities;

  /// Entities that have at least one project; null until known (then the
  /// entity step shows everything rather than nothing).
  final Set<String>? entityIdsWithProjects;
  final Entity? entity;
  final List<Project> projects;
  final Project? project;
  final List<ProjectItem> items;

  /// projectItemId -> quantity delivered. Only entries > 0 go on the سند.
  final Map<String, double> quantities;

  /// Rows whose quantity text isn't a number, with that text (so a card that
  /// scrolls away and back still shows what was typed). Blocks submitting:
  /// a typo must never silently drop a line from the سند.
  final Map<String, String> invalid;

  /// projectItemId -> free-text note for that line, shown in the PDF's
  /// ملاحظات column. Entries only exist for items with a non-empty note.
  final Map<String, String> itemNotes;

  /// Editing: lines of the old سند no longer in the quotation (not carried).
  final int droppedFromOriginal;
  final bool submitting;
  final String? error;

  /// True: the سند PDF's date is left blank for the receiving side to fill
  /// in by hand at delivery. False (default): stamped with today's date.
  final bool handwrittenDate;

  /// Set once the سند is filed, so the screen can preview/share it.
  final Uint8List? pdfBytes;
  final String? receiptId;

  const CreateDeliveryReceiptState({
    this.loading = false,
    this.entities = const [],
    this.entityIdsWithProjects,
    this.entity,
    this.projects = const [],
    this.project,
    this.items = const [],
    this.quantities = const {},
    this.invalid = const {},
    this.itemNotes = const {},
    this.droppedFromOriginal = 0,
    this.submitting = false,
    this.error,
    this.handwrittenDate = false,
    this.pdfBytes,
    this.receiptId,
  });

  /// What the entity step lists: only entities a سند can be filed for.
  List<Entity> get pickableEntities {
    final ids = entityIdsWithProjects;
    return ids == null ? entities : entities.where((e) => ids.contains(e.id)).toList();
  }

  int get selectedCount => quantities.values.where((q) => q > 0).length;

  bool get canSubmit =>
      entity != null &&
      project != null &&
      invalid.isEmpty &&
      quantities.values.any((q) => q > 0) &&
      !submitting;

  CreateDeliveryReceiptState copyWith({
    bool? loading,
    List<Entity>? entities,
    Set<String>? entityIdsWithProjects,
    Entity? entity,
    List<Project>? projects,
    Project? project,
    List<ProjectItem>? items,
    Map<String, double>? quantities,
    Map<String, String>? invalid,
    Map<String, String>? itemNotes,
    int? droppedFromOriginal,
    bool? submitting,
    String? error,
    bool clearError = false,
    Uint8List? pdfBytes,
    String? receiptId,
    bool? handwrittenDate,
  }) {
    return CreateDeliveryReceiptState(
      loading: loading ?? this.loading,
      entities: entities ?? this.entities,
      entityIdsWithProjects: entityIdsWithProjects ?? this.entityIdsWithProjects,
      entity: entity ?? this.entity,
      projects: projects ?? this.projects,
      project: project ?? this.project,
      items: items ?? this.items,
      quantities: quantities ?? this.quantities,
      invalid: invalid ?? this.invalid,
      itemNotes: itemNotes ?? this.itemNotes,
      droppedFromOriginal: droppedFromOriginal ?? this.droppedFromOriginal,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      pdfBytes: pdfBytes ?? this.pdfBytes,
      receiptId: receiptId ?? this.receiptId,
      handwrittenDate: handwrittenDate ?? this.handwrittenDate,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        entities,
        entityIdsWithProjects,
        entity,
        projects,
        project,
        items,
        quantities,
        invalid,
        itemNotes,
        droppedFromOriginal,
        submitting,
        error,
        receiptId,
        handwrittenDate,
      ];
}
