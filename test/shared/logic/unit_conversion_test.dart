import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/logic/unit_conversion.dart';

void main() {
  group('convertQuantity', () {
    test('same unit returns the value unchanged', () {
      expect(convertQuantity(5, QuantityUnit.kilogram, QuantityUnit.kilogram), 5);
    });

    test('converts within mass', () {
      expect(convertQuantity(1, QuantityUnit.kilogram, QuantityUnit.gram), 1000);
      expect(convertQuantity(1500, QuantityUnit.gram, QuantityUnit.kilogram), 1.5);
      expect(convertQuantity(2, QuantityUnit.ton, QuantityUnit.kilogram), 2000);
    });

    test('converts within volume', () {
      expect(convertQuantity(1, QuantityUnit.liter, QuantityUnit.milliliter), 1000);
      expect(convertQuantity(250, QuantityUnit.milliliter, QuantityUnit.liter), 0.25);
    });

    test('refuses to convert across dimensions', () {
      expect(convertQuantity(1, QuantityUnit.kilogram, QuantityUnit.liter), isNull);
      expect(convertQuantity(1, QuantityUnit.piece, QuantityUnit.gram), isNull);
    });
  });

  group('QuantityUnit.tryParse / ofDimension', () {
    test('parses a stored enum name back, and rejects unknown text', () {
      expect(QuantityUnit.tryParse('kilogram'), QuantityUnit.kilogram);
      expect(QuantityUnit.tryParse('كجم'), isNull, reason: 'stores the enum name, not the Arabic label');
      expect(QuantityUnit.tryParse(null), isNull);
    });

    test('ofDimension lists only same-dimension units, for a delivered-unit picker', () {
      expect(QuantityUnit.ofDimension(UnitDimension.mass),
          containsAll([QuantityUnit.kilogram, QuantityUnit.gram, QuantityUnit.ton]));
      expect(QuantityUnit.ofDimension(UnitDimension.mass), isNot(contains(QuantityUnit.liter)));
    });
  });

  group('calculateReceiptQuantity', () {
    test('the worked example from the spec: 2.75 kg × 4 delivered against a 1.65 kg × 4 registered كرتون', () {
      const registered = RegisteredPackaging(packSize: 1.65, packCount: 4, baseUnit: QuantityUnit.kilogram);
      final result = calculateReceiptQuantity(
        registered: registered,
        deliveredQuantity: 2.75,
        deliveredUnit: QuantityUnit.kilogram,
        deliveredPackCount: 4,
      );
      expect(result, closeTo(1.6667, 0.0001));
    });

    test('converts the delivered side when its unit differs from the registered base unit', () {
      const registered = RegisteredPackaging(packSize: 1.65, packCount: 4, baseUnit: QuantityUnit.kilogram);
      final result = calculateReceiptQuantity(
        registered: registered,
        deliveredQuantity: 2750, // same 2.75 kg, typed in grams
        deliveredUnit: QuantityUnit.gram,
        deliveredPackCount: 4,
      );
      expect(result, closeTo(1.6667, 0.0001));
    });

    test('an exact match converts to exactly 1', () {
      const registered = RegisteredPackaging(packSize: 1.65, packCount: 4, baseUnit: QuantityUnit.kilogram);
      final result = calculateReceiptQuantity(
        registered: registered,
        deliveredQuantity: 1.65,
        deliveredUnit: QuantityUnit.kilogram,
        deliveredPackCount: 4,
      );
      expect(result, closeTo(1, 0.0000001));
    });

    test('returns null rather than a meaningless number for an incompatible unit', () {
      const registered = RegisteredPackaging(packSize: 1.65, packCount: 4, baseUnit: QuantityUnit.kilogram);
      final result = calculateReceiptQuantity(
        registered: registered,
        deliveredQuantity: 5,
        deliveredUnit: QuantityUnit.liter,
        deliveredPackCount: 1,
      );
      expect(result, isNull);
    });

    test('pieces-per-pack packaging works the same way (item 6 of the spec)', () {
      // Registered: 1 شد = 24 حبة. Delivered: 3 packs of 20 pieces each.
      const registered = RegisteredPackaging(packSize: 24, packCount: 1, baseUnit: QuantityUnit.piece);
      final result = calculateReceiptQuantity(
        registered: registered,
        deliveredQuantity: 20,
        deliveredUnit: QuantityUnit.piece,
        deliveredPackCount: 3,
      );
      expect(result, closeTo(2.5, 0.0001));
    });
  });
}
