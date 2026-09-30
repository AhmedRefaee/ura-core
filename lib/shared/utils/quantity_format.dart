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

/// Two decimals with thousands separators, as on the paper quotation.
String formatMoney(double v) {
  final fixed = v.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0 && whole[i - 1] != '-') buf.write(',');
    buf.write(whole[i]);
  }
  return '$buf${fixed.substring(dot)}';
}

/// Parses a number as people type it on an Arabic keyboard: Arabic-Indic
/// (٠-٩) and Persian (۰-۹) digits, "٫" or "." as the decimal point, and ","
/// / "٬" / spaces as thousands separators ("1,000" is a thousand, not 1.0).
/// Returns null for anything else -- callers show an error rather than
/// silently treating a typo as zero.
double? parseLocalizedNumber(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.trim().runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buf.write(rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buf.write(rune - 0x06F0);
    } else {
      final ch = String.fromCharCode(rune);
      if (ch == '٫') {
        buf.write('.');
      } else if (ch != ',' && ch != '٬' && ch.trim().isNotEmpty) {
        buf.write(ch);
      }
    }
  }
  final s = buf.toString();
  return s.isEmpty ? null : double.tryParse(s);
}

/// Rounds a money/quantity product to 2 decimals (3 × 1.1 is 3.3, not
/// 3.3000000000000003).
double round2(double v) => (v * 100).round() / 100;

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
