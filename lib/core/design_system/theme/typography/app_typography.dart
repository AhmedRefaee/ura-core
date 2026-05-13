import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography configuration for URA CORE application.
/// Uses Cairo font for Arabic language support.
class AppTypography {
  const AppTypography._();

  /// Get the Cairo text theme for the given brightness.
  static TextTheme get textTheme => GoogleFonts.cairoTextTheme();

  /// Get a specific text style with Cairo font.
  static TextStyle getTextStyle({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
  }) {
    return GoogleFonts.cairo(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }
}
