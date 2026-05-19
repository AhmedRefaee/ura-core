import '../data/models/bulk_edit_item_model.dart';
import '../data/models/bulk_edit_error_model.dart';

abstract class BulkEditExcelState {}

class BulkEditExcelInitial extends BulkEditExcelState {}

class BulkEditExcelExporting extends BulkEditExcelState {}

class BulkEditExcelParsing extends BulkEditExcelState {}

class BulkEditExcelParsed extends BulkEditExcelState {
  final List<BulkEditItemModel> validItems;
  final List<BulkEditErrorModel> invalidItems;
  final int totalRows;

  BulkEditExcelParsed({
    required this.validItems,
    required this.invalidItems,
    required this.totalRows,
  });
}

class BulkEditExcelSaving extends BulkEditExcelState {}

class BulkEditExcelDone extends BulkEditExcelState {
  final int updatedCount;
  BulkEditExcelDone(this.updatedCount);
}

class BulkEditExcelError extends BulkEditExcelState {
  final String message;
  BulkEditExcelError(this.message);
}
