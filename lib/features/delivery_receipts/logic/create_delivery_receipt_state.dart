part of 'create_delivery_receipt_cubit.dart';

class CreateDeliveryReceiptState extends Equatable {
  final bool loading;
  final List<Entity> entities;
  final Entity? entity;
  final List<Project> projects;
  final Project? project;
  final List<ProjectItem> items;

  /// projectItemId -> quantity delivered. Only entries > 0 go on the سند.
  final Map<String, double> quantities;
  final bool submitting;
  final String? error;

  /// Set once the سند is filed, so the screen can preview/share it.
  final Uint8List? pdfBytes;
  final String? receiptId;

  const CreateDeliveryReceiptState({
    this.loading = false,
    this.entities = const [],
    this.entity,
    this.projects = const [],
    this.project,
    this.items = const [],
    this.quantities = const {},
    this.submitting = false,
    this.error,
    this.pdfBytes,
    this.receiptId,
  });

  bool get canSubmit =>
      entity != null && project != null && quantities.values.any((q) => q > 0) && !submitting;

  CreateDeliveryReceiptState copyWith({
    bool? loading,
    List<Entity>? entities,
    Entity? entity,
    List<Project>? projects,
    Project? project,
    List<ProjectItem>? items,
    Map<String, double>? quantities,
    bool? submitting,
    String? error,
    bool clearError = false,
    Uint8List? pdfBytes,
    String? receiptId,
  }) {
    return CreateDeliveryReceiptState(
      loading: loading ?? this.loading,
      entities: entities ?? this.entities,
      entity: entity ?? this.entity,
      projects: projects ?? this.projects,
      project: project ?? this.project,
      items: items ?? this.items,
      quantities: quantities ?? this.quantities,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      pdfBytes: pdfBytes ?? this.pdfBytes,
      receiptId: receiptId ?? this.receiptId,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        entities,
        entity,
        projects,
        project,
        items,
        quantities,
        submitting,
        error,
        receiptId,
      ];
}
