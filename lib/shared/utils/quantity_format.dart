import 'package:flutter/services.dart';

/// Formats a quantity for display, trimming trailing zeros.
///
/// Quantities are stored as `double` to support decimals (e.g. 3.5 kg,
/// 0.25 L), but whole numbers should render cleanly without a `.0` suffix.
///
/// Examples: `3.0 -> "3"`, `3.50 -> "3.5"`, `0.25 -> "0.25"`.
String formatQty(num q) {
  // Round to 2 decimals (the input precision) then strip trailing zeros.
  var s = q.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), ''); // drop trailing zeros
    s = s.replaceFirst(RegExp(r'\.$'), ''); // drop a dangling dot
  }
  return s;
}

/// Parses user-entered text into a quantity, or `null` if invalid.
double? parseQty(String? text) {
  if (text == null) return null;
  return double.tryParse(text.trim());
}

/// Input formatter allowing digits and a single decimal point with at most
/// two decimal places. Replaces [FilteringTextInputFormatter.digitsOnly] on
/// quantity fields so decimals can be typed.
final TextInputFormatter quantityInputFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));
