import 'imported_entity_model.dart';

class EntityImportErrorModel {
  final int rowNumber;
  final List<String> errors;
  final ImportedEntityModel rawData;

  const EntityImportErrorModel({
    required this.rowNumber,
    required this.errors,
    required this.rawData,
  });
}
