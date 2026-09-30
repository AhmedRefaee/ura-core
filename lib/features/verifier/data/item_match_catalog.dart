import '../../../shared/models/inventory_item.dart';

/// The inventory as the model sees it.
///
/// Rows go out as pipe-delimited lines keyed by a short integer ref rather than
/// as JSON objects keyed by a 36-character UUID. An id costs roughly seventeen
/// tokens per row and helps the model recognise an Arabic product name not at
/// all — it only has to survive the round trip intact, which a ref does just as
/// well. [idByRef] turns the model's answer back into real ids, and doubles as
/// the allow-list it replaces: a ref that was never issued resolves to nothing,
/// so an invented one cannot reach the order.
class ItemMatchCatalog {
  /// The block handed to the model, header line included.
  final String block;

  final Map<int, String> _ids;

  const ItemMatchCatalog._(this.block, this._ids);

  factory ItemMatchCatalog.of(List<InventoryItem> inventory) {
    final ids = <int, String>{};
    final lines = <String>[];
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      final ref = i + 1;
      ids[ref] = row.id;
      lines.add(
        [
          '$ref',
          row.itemName,
          row.unit,
          row.category ?? '',
          row.sku ?? '',
        ].map(_clean).join('|'),
      );
    }
    return ItemMatchCatalog._([_header, ...lines].join('\n'), ids);
  }

  // brand, variety and packaging are deliberately NOT sent. They were added on
  // 2026-09-02 and removed the same day: they grew this block by 27% on every
  // request, and the benefit was never demonstrated — the offline report showed
  // no change at all locally, and nothing measured the model side. The columns
  // still exist and are used by the inventory screens and the no-duplicates
  // rule; they just do not ride along on every AI call. Don't re-add them
  // without a measurement showing the model answers better with them.
  static const _header =
      'Inventory — one item per line, as ref|name|unit|category|sku:';

  /// A pipe or a newline inside a product name would silently shift every
  /// field after it onto the wrong column.
  static String _clean(String field) =>
      field.replaceAll(RegExp(r'[|\r\n]+'), ' ').trim();

  /// Resolves one of the model's refs back to a real inventory id.
  ///
  /// The schema asks for an integer, but a model can still answer `'12'` or
  /// `12.0`. Anything that doesn't name a ref actually issued — a hallucinated
  /// number, a product name where a ref belongs, a UUID it invented — resolves
  /// to null, and the caller drops it.
  String? idByRef(Object? raw) {
    final ref = raw is num ? raw : num.tryParse(raw?.toString().trim() ?? '');
    if (ref == null || ref != ref.roundToDouble()) return null;
    return _ids[ref.toInt()];
  }

  /// How many rows the model was shown.
  int get rowCount => _ids.length;
}
