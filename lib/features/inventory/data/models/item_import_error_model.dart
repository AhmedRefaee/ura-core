import 'imported_item_model.dart';

class ItemImportErrorModel {
  final int rowNumber;
  final List<String> errors;
  final ImportedItemModel rawData;

  const ItemImportErrorModel({
    required this.rowNumber,
    required this.errors,
    required this.rawData,
  });
}
