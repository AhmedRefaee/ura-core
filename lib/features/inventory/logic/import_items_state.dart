import '../data/models/imported_item_model.dart';
import '../data/models/item_import_error_model.dart';

abstract class ImportItemsState {}

class ImportItemsInitial extends ImportItemsState {}

class ImportItemsParsing extends ImportItemsState {}

class ImportItemsParsed extends ImportItemsState {
  final List<ImportedItemModel> validItems;
  final List<ItemImportErrorModel> invalidItems;
  final int totalRows;

  ImportItemsParsed({
    required this.validItems,
    required this.invalidItems,
    required this.totalRows,
  });
}

class ImportItemsSaving extends ImportItemsState {}

class ImportItemsDone extends ImportItemsState {
  final int insertedCount;
  ImportItemsDone(this.insertedCount);
}

class ImportItemsError extends ImportItemsState {
  final String message;
  ImportItemsError(this.message);
}
