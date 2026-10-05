part of 'create_delivery_receipt_cubit.dart';

/// today (default): stamped with the day the سند is filed.
/// blank: the date line prints empty, for the receiving side to fill in by
/// hand at delivery.
/// custom: a specific date the creator picked themselves.
enum ReceiptDateMode { today, blank, custom }

/// One سند already created during a submit() that split the picks by
/// category -- see CreateDeliveryReceiptCubit.submit/advanceToNextReceipt.
/// Only the first is shown immediately; the rest sit in
/// [CreateDeliveryReceiptState.remainingReceipts] until the rep dismisses
/// the one on screen.
typedef FiledReceipt = ({String receiptId, Uint8List pdfBytes, String categoryLabel});

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

  final ReceiptDateMode dateMode;

  /// Only meaningful when [dateMode] is [ReceiptDateMode.custom].
  final DateTime? customDate;

  /// Set once the سند is filed, so the screen can preview/share it.
  final Uint8List? pdfBytes;
  final String? receiptId;

  /// Settings-menu toggle: file one سند per category instead of a single
  /// one covering every picked item. Forced off while editing (see submit())
  /// -- a replace operation has exactly one old سند to replace, so splitting
  /// the replacement into several has no sane meaning.
  final bool splitByCategory;

  /// سندات already created by the current submit() that haven't been shown
  /// yet -- only populated right after a split submit, drained one at a
  /// time by advanceToNextReceipt() as the rep dismisses each preview.
  final List<FiledReceipt> remainingReceipts;

  /// The category of the سند currently in [receiptId]/[pdfBytes], and how
  /// many this submit() produced in total -- both only meaningful once a
  /// سند has been filed, for _FiledView's "(2 من 3) — الفئة" title.
  final String? currentCategoryLabel;
  final int totalReceiptsThisSubmit;

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
    this.dateMode = ReceiptDateMode.today,
    this.customDate,
    this.pdfBytes,
    this.receiptId,
    this.splitByCategory = false,
    this.remainingReceipts = const [],
    this.currentCategoryLabel,
    this.totalReceiptsThisSubmit = 1,
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

  /// How many separate سندات splitByCategory would actually produce right
  /// now, for the settings dialog's preview line. Counts distinct
  /// categories among picked items only -- an empty category string is
  /// still one group (uncategorized items), same as submit()'s grouping.
  int get chosenCategoryCount =>
      items.where((i) => (quantities[i.id] ?? 0) > 0).map((i) => i.category).toSet().length;

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
    ReceiptDateMode? dateMode,
    DateTime? customDate,
    // Switching to today/blank must actually drop a previously-picked
    // custom date, not just stop showing it -- customDate ?? this.customDate
    // alone could never clear it once set.
    bool clearCustomDate = false,
    bool? splitByCategory,
    List<FiledReceipt>? remainingReceipts,
    String? currentCategoryLabel,
    int? totalReceiptsThisSubmit,
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
      dateMode: dateMode ?? this.dateMode,
      customDate: clearCustomDate ? null : (customDate ?? this.customDate),
      splitByCategory: splitByCategory ?? this.splitByCategory,
      remainingReceipts: remainingReceipts ?? this.remainingReceipts,
      currentCategoryLabel: currentCategoryLabel ?? this.currentCategoryLabel,
      totalReceiptsThisSubmit: totalReceiptsThisSubmit ?? this.totalReceiptsThisSubmit,
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
        dateMode,
        customDate,
        splitByCategory,
        remainingReceipts,
        currentCategoryLabel,
        totalReceiptsThisSubmit,
      ];
}
