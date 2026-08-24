import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/verifier/data/item_match_catalog.dart';
import 'package:ura_core/shared/models/inventory_item.dart';

void main() {
  const water330 = InventoryItem(
    id: 'id-water-330',
    itemName: 'مياه نوفا 330 مل',
    sku: 'W330',
    quantity: 50,
    unit: 'كرتونة',
    category: 'مشروبات',
  );
  const water500 = InventoryItem(
    id: 'id-water-500',
    itemName: 'مياه نوفا 500 مل',
    quantity: 20,
    unit: 'كرتونة',
    category: 'مشروبات',
  );
  const soap = InventoryItem(
    id: 'id-soap',
    itemName: 'صابون لوكس',
    quantity: 8,
    unit: 'علبة',
  );

  group('the block the model sees', () {
    test('is one ref-keyed line per row, with a header', () {
      final catalog = ItemMatchCatalog.of([water330, water500, soap]);
      final lines = catalog.block.split('\n');

      expect(lines.first, startsWith('Inventory'));
      expect(lines[1], '1|مياه نوفا 330 مل|كرتونة|مشروبات|W330');
      expect(lines[2], '2|مياه نوفا 500 مل|كرتونة|مشروبات|');
      expect(lines[3], '3|صابون لوكس|علبة||');
      expect(catalog.rowCount, 3);
    });

    test('never carries an inventory id', () {
      final catalog = ItemMatchCatalog.of([water330, water500, soap]);

      expect(catalog.block, isNot(contains('id-water-330')));
      expect(catalog.block, isNot(contains('id-soap')));
    });

    test('a pipe or newline in a name cannot shift the columns', () {
      const nasty = InventoryItem(
        id: 'id-nasty',
        itemName: 'مياه | نوفا\n330',
        quantity: 1,
        unit: 'كرتونة',
      );

      final row = ItemMatchCatalog.of([nasty]).block.split('\n')[1];

      expect(row.split('|').length, 5);
      expect(row, startsWith('1|'));
    });

    test('is byte-identical for the same inventory, so it can be cached', () {
      expect(
        ItemMatchCatalog.of([water330, soap]).block,
        ItemMatchCatalog.of([water330, soap]).block,
      );
    });
  });

  group('resolving the refs the model answers with', () {
    final catalog = ItemMatchCatalog.of([water330, water500, soap]);

    test('an issued ref resolves to its row', () {
      expect(catalog.idByRef(1), 'id-water-330');
      expect(catalog.idByRef(3), 'id-soap');
    });

    test('accepts the shapes a model actually returns', () {
      expect(catalog.idByRef('2'), 'id-water-500');
      expect(catalog.idByRef(2.0), 'id-water-500');
      expect(catalog.idByRef(' 2 '), 'id-water-500');
    });

    test('anything never issued resolves to nothing', () {
      expect(catalog.idByRef(0), isNull, reason: 'refs start at 1');
      expect(catalog.idByRef(99), isNull);
      expect(catalog.idByRef(-1), isNull);
      expect(catalog.idByRef(2.5), isNull);
      expect(catalog.idByRef(null), isNull);
      expect(catalog.idByRef(''), isNull);
      expect(catalog.idByRef('مياه نوفا'), isNull, reason: 'a name is not a ref');
      expect(catalog.idByRef('id-water-330'), isNull, reason: 'nor is an id it guessed');
    });
  });
}
