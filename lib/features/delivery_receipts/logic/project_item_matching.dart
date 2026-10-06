import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/project_item.dart';

extension ProjectItemMatching on ProjectItem {
  /// This quotation line as the row the item matcher understands, so a pasted
  /// message can be matched against a project's quotation by the same local
  /// matcher and Gemini fallback that match against inventory. The id carries
  /// through, which is how a match finds its way back to the line.
  InventoryItem toMatchable() => InventoryItem(
        id: id,
        itemName: itemName,
        quantity: quantity,
        unit: unit,
        category: category.isEmpty ? null : category,
        description: description,
      );
}
