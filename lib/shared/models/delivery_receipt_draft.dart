import 'package:equatable/equatable.dart';

/// A سند's progress saved locally on this device before anything is
/// actually filed -- see CreateDeliveryReceiptCubit.saveDraft(). Nothing
/// here ever reaches the server; it's a pure "pause and continue later"
/// convenience, deleted once the real سند it became is actually filed (or
/// removed by hand from the drafts list).
class DeliveryReceiptDraft extends Equatable {
  final String id;
  final String entityId;
  final String entityName;
  final String projectId;
  final String projectName;
  final String? orderId;

  /// projectItemId -> quantity delivered, exactly as CreateDeliveryReceiptState
  /// holds them.
  final Map<String, double> quantities;
  final Map<String, String> itemNotes;

  /// Stores ReceiptDateMode.name rather than the enum itself, so this model
  /// doesn't need to depend on the cubit's part file.
  final String dateMode;
  final DateTime? customDate;
  final bool splitByCategory;
  final DateTime savedAt;

  const DeliveryReceiptDraft({
    required this.id,
    required this.entityId,
    required this.entityName,
    required this.projectId,
    required this.projectName,
    this.orderId,
    required this.quantities,
    required this.itemNotes,
    required this.dateMode,
    this.customDate,
    required this.splitByCategory,
    required this.savedAt,
  });

  int get itemCount => quantities.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityId': entityId,
        'entityName': entityName,
        'projectId': projectId,
        'projectName': projectName,
        'orderId': orderId,
        'quantities': quantities,
        'itemNotes': itemNotes,
        'dateMode': dateMode,
        'customDate': customDate?.toIso8601String(),
        'splitByCategory': splitByCategory,
        'savedAt': savedAt.toIso8601String(),
      };

  factory DeliveryReceiptDraft.fromJson(Map<String, dynamic> json) => DeliveryReceiptDraft(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        entityName: json['entityName'] as String,
        projectId: json['projectId'] as String,
        projectName: json['projectName'] as String,
        orderId: json['orderId'] as String?,
        quantities: (json['quantities'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        itemNotes: (json['itemNotes'] as Map).map((k, v) => MapEntry(k as String, v as String)),
        dateMode: json['dateMode'] as String,
        customDate: json['customDate'] == null ? null : DateTime.parse(json['customDate'] as String),
        splitByCategory: json['splitByCategory'] as bool? ?? false,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        entityId,
        entityName,
        projectId,
        projectName,
        orderId,
        quantities,
        itemNotes,
        dateMode,
        customDate,
        splitByCategory,
        savedAt,
      ];
}
