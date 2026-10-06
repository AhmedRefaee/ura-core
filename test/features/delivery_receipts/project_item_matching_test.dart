import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/delivery_receipts/logic/project_item_matching.dart';
import 'package:ura_core/shared/models/project_item.dart';

void main() {
  test('a quotation line becomes a matchable row under the same id', () {
    const line = ProjectItem(
      id: 'i1',
      projectId: 'p1',
      category: 'ألبان',
      itemName: 'لبنة',
      quantity: 1100,
      unit: 'كرتون',
      description: 'كرتون 2.75*4كيلو جرام',
    );

    final row = line.toMatchable();

    expect(row.id, 'i1', reason: 'the id is how a match finds its way back to the line');
    expect(row.itemName, 'لبنة');
    expect(row.unit, 'كرتون');
    expect(row.category, 'ألبان');
  });

  test('an uncategorized line has no category rather than an empty one', () {
    const line = ProjectItem(id: 'i2', projectId: 'p1', itemName: 'قشطة', quantity: 12, unit: 'كرتون');
    expect(line.toMatchable().category, isNull);
  });
}
