import '../models/project_item.dart';

/// Physical dimension a [QuantityUnit] measures. Converting between units of
/// different dimensions (e.g. kg -> L) is never valid -- see [convertQuantity].
enum UnitDimension { mass, volume, count }

/// A small, closed vocabulary of units a بند's packaging can be measured in.
/// Adding a unit is one more enum value with its dimension and factor to
/// that dimension's own base unit (kg for mass, L for volume, a single piece
/// for count) -- nothing else in this file needs to change.
enum QuantityUnit {
  kilogram(UnitDimension.mass, 1, 'كجم'),
  gram(UnitDimension.mass, 0.001, 'جم'),
  ton(UnitDimension.mass, 1000, 'طن'),
  liter(UnitDimension.volume, 1, 'لتر'),
  milliliter(UnitDimension.volume, 0.001, 'مل'),
  piece(UnitDimension.count, 1, 'حبة');

  final UnitDimension dimension;

  /// Multiply a value in this unit by this factor to get the dimension's
  /// base unit.
  final double factorToBase;
  final String label;
  const QuantityUnit(this.dimension, this.factorToBase, this.label);

  /// Units sharing this one's dimension -- what a delivered-unit picker
  /// should be limited to once the registered item's base unit is known.
  static List<QuantityUnit> ofDimension(UnitDimension d) =>
      values.where((u) => u.dimension == d).toList();

  /// Parses a stored name (`QuantityUnit.kilogram.name` == `'kilogram'`)
  /// back into a unit. Null for anything unrecognized, rather than throwing
  /// on old data or a typo'd column.
  static QuantityUnit? tryParse(String? name) {
    if (name == null) return null;
    for (final u in values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

/// Converts [value] from [from] to [to]. Null when the two units measure
/// different physical things (kg -> L) -- a safe refusal, never a
/// meaningless number.
double? convertQuantity(double value, QuantityUnit from, QuantityUnit to) {
  if (from.dimension != to.dimension) return null;
  if (from == to) return value;
  return (value * from.factorToBase) / to.factorToBase;
}

/// What "1 registered unit" (e.g. 1 كرتون) amounts to: [packSize] of
/// [baseUnit], [packCount] times over -- e.g. 1.65 kg per pack × 4 packs =
/// 6.6 kg in one registered كرتون.
class RegisteredPackaging {
  final double packSize;
  final double packCount;
  final QuantityUnit baseUnit;

  const RegisteredPackaging({
    required this.packSize,
    required this.packCount,
    required this.baseUnit,
  });

  double get totalInBaseUnit => packSize * packCount;
}

/// Reads a [ProjectItem]'s packaging columns into a [RegisteredPackaging],
/// or null if the item was never set up with one (the common case --
/// سند quantity entry for such items is unaffected, exactly as before this
/// feature existed).
RegisteredPackaging? registeredPackagingOf(ProjectItem item) {
  final size = item.packagingUnitSize;
  final count = item.packagingUnitCount;
  final unit = QuantityUnit.tryParse(item.packagingBaseUnit);
  if (size == null || count == null || unit == null || size <= 0 || count <= 0) {
    return null;
  }
  return RegisteredPackaging(packSize: size, packCount: count, baseUnit: unit);
}

/// How many registered units [deliveredQuantity] of [deliveredUnit], across
/// [deliveredPackCount] packs, amounts to against [registered]'s own
/// packaging.
///
/// `2.75 kg × 4 packs` delivered against a `1.65 kg × 4 pack` registered
/// unit: `(2.75×4) / (1.65×4)` ≈ `1.67`.
///
/// Null when [deliveredUnit] isn't [registered]'s physical dimension (e.g.
/// delivered in litres against a kg-registered item) -- there's no sensible
/// number to return, and the caller should say so rather than show one.
double? calculateReceiptQuantity({
  required RegisteredPackaging registered,
  required double deliveredQuantity,
  required QuantityUnit deliveredUnit,
  required double deliveredPackCount,
}) {
  final deliveredInBase = convertQuantity(deliveredQuantity, deliveredUnit, registered.baseUnit);
  if (deliveredInBase == null || registered.totalInBaseUnit == 0) return null;
  return (deliveredInBase * deliveredPackCount) / registered.totalInBaseUnit;
}
