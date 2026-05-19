import 'bulk_edit_item_model.dart';

class BulkEditErrorModel {
  final int rowNumber;
  final List<String> errors;
  final BulkEditItemModel rawData;

  const BulkEditErrorModel({
    required this.rowNumber,
    required this.errors,
    required this.rawData,
  });
}
