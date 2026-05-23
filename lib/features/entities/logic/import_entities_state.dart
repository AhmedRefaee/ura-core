import '../data/models/imported_entity_model.dart';
import '../data/models/entity_import_error_model.dart';

abstract class ImportEntitiesState {}

class ImportEntitiesInitial extends ImportEntitiesState {}

class ImportEntitiesExporting extends ImportEntitiesState {}

class ImportEntitiesParsing extends ImportEntitiesState {}

class ImportEntitiesParsed extends ImportEntitiesState {
  final List<ImportedEntityModel> validItems;
  final List<EntityImportErrorModel> invalidItems;
  final int totalRows;

  ImportEntitiesParsed({
    required this.validItems,
    required this.invalidItems,
    required this.totalRows,
  });
}

class ImportEntitiesSaving extends ImportEntitiesState {}

class ImportEntitiesDone extends ImportEntitiesState {
  final int updatedCount;
  final int insertedCount;

  ImportEntitiesDone({required this.updatedCount, required this.insertedCount});

  int get totalCount => updatedCount + insertedCount;
}

class ImportEntitiesError extends ImportEntitiesState {
  final String message;
  ImportEntitiesError(this.message);
}
