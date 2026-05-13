import 'package:flutter/material.dart';
import 'theme_data_light.dart';
import 'theme_data_dark.dart';

/// Main theme configuration for URA CORE application.
/// Provides light and dark themes with consistent styling.
class AppTheme {
  const AppTheme._();

  /// Get the light theme.
  static ThemeData get light => ThemeDataLight.theme;

  /// Get the dark theme.
  static ThemeData get dark => ThemeDataDark.theme;

  /// Get theme from BuildContext.
  static ThemeData of(BuildContext context) {
    return Theme.of(context);
  }

  /// Check if current theme is dark.
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// Check if current theme is light.
  static bool isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }
}
