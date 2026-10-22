// A typed line is the only thing the verifier writes on an outbound order,
// so its payload must survive editing without losing what storage or the
// rep later read from it (brand, variety, packaging).
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/draft_order_item.dart';

void main() {
  test('a typed line carries name, unit and quantity as JSON', () {
    final item = DraftOrderItem.typed(name: ' شاي ربيع ', unit: 'كرتون', quantity: 2);
    final json = jsonDecode(item.customDescription!) as Map<String, dynamic>;
    expect(item.isCustom, isTrue);
    expect(json['name'], 'شاي ربيع');
    expect(json['unit'], 'كرتون');
    expect(json['qty'], 2);
    expect(item.typedName, 'شاي ربيع');
    expect(item.displayName, 'شاي ربيع');
  });

  test('no unit written stays unwritten (readers default to قطعة)', () {
    final item = DraftOrderItem.typed(name: 'سكر', quantity: 1);
    expect(item.typedUnit, '');
    expect((jsonDecode(item.customDescription!) as Map).containsKey('unit'), isFalse);
  });

  test('editing keeps the rest of the payload', () {
    final withBrand = DraftOrderItem(
      quantity: 1,
      isCustom: true,
      customDescription: jsonEncode({'name': 'شاي', 'unit': 'علبة', 'brand': 'ربيع'}),
    );
    final edited = withBrand.withTyped(name: 'شاي أخضر', quantity: 4);
    final json = jsonDecode(edited.customDescription!) as Map<String, dynamic>;
    expect(json['brand'], 'ربيع');
    expect(json['unit'], 'علبة');
    expect(json['name'], 'شاي أخضر');
    expect(edited.quantity, 4);
  });

  test('complete needs a name and a quantity above zero', () {
    expect(DraftOrderItem.typed(name: '', quantity: 1).isComplete, isFalse);
    expect(DraftOrderItem.typed(name: 'سكر', quantity: 0).isComplete, isFalse);
    expect(DraftOrderItem.typed(name: 'سكر', quantity: 1).isComplete, isTrue);
    expect(
      const DraftOrderItem(inventoryId: 'inv', inventoryName: 'سكر', quantity: 2, isCustom: false)
          .isComplete,
      isTrue,
    );
  });

  test('every typed line gets its own row key, and edits keep it', () {
    final a = DraftOrderItem.typed(name: 'أ', quantity: 1);
    final b = DraftOrderItem.typed(name: 'ب', quantity: 1);
    expect(a.rowKey, isNot(b.rowKey));
    expect(a.withTyped(name: 'ج').rowKey, a.rowKey);
    expect(a.withQuantity(5).rowKey, a.rowKey);
  });
}
