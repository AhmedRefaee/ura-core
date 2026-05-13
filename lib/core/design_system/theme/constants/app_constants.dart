import 'package:flutter/material.dart';

/// App-wide constants for URA CORE application.
/// Includes border radius, elevation, and other UI constants.
class AppConstants {
  const AppConstants._();

  // ========================================
  // Border Radius
  // ========================================
  static const double borderRadiusXSmall = 4.0;
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 16.0;
  static const double borderRadiusXLarge = 20.0;
  static const double borderRadiusXXLarge = 24.0;
  static const double borderRadiusXXXLarge = 32.0;
  static const double borderRadiusCircle = 999.0;

  static const BorderRadius borderRadiusXSmallRadius =
      BorderRadius.all(Radius.circular(borderRadiusXSmall));
  static const BorderRadius borderRadiusSmallRadius =
      BorderRadius.all(Radius.circular(borderRadiusSmall));
  static const BorderRadius borderRadiusMediumRadius =
      BorderRadius.all(Radius.circular(borderRadiusMedium));
  static const BorderRadius borderRadiusLargeRadius =
      BorderRadius.all(Radius.circular(borderRadiusLarge));
  static const BorderRadius borderRadiusXLargeRadius =
      BorderRadius.all(Radius.circular(borderRadiusXLarge));
  static const BorderRadius borderRadiusXXLargeRadius =
      BorderRadius.all(Radius.circular(borderRadiusXXLarge));
  static const BorderRadius borderRadiusXXXLargeRadius =
      BorderRadius.all(Radius.circular(borderRadiusXXXLarge));
  static const BorderRadius borderRadiusCircleRadius =
      BorderRadius.all(Radius.circular(borderRadiusCircle));

  // ========================================
  // Elevation
  // ========================================
  static const double elevation0 = 0.0;
  static const double elevation1 = 1.0;
  static const double elevation2 = 2.0;
  static const double elevation3 = 3.0;
  static const double elevation4 = 4.0;
  static const double elevation6 = 6.0;
  static const double elevation8 = 8.0;
  static const double elevation12 = 12.0;
  static const double elevation16 = 16.0;
  static const double elevation24 = 24.0;

  // ========================================
  // Animation Duration
  // ========================================
  static const Duration animationDurationFast = Duration(milliseconds: 150);
  static const Duration animationDurationNormal = Duration(milliseconds: 300);
  static const Duration animationDurationSlow = Duration(milliseconds: 500);

  // ========================================
  // Icon Sizes
  // ========================================
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 24.0;
  static const double iconSizeLarge = 32.0;
  static const double iconSizeXLarge = 48.0;

  // ========================================
  // Button Heights
  // ========================================
  static const double buttonHeight = 48.0;
  static const double buttonHeightSmall = 36.0;

  // ========================================
  // Input Field Heights
  // ========================================
  static const double inputFieldHeight = 56.0;
  static const double inputFieldHeightSmall = 48.0;

  // ========================================
  // Card Elevation
  // ========================================
  static const double cardElevation = 1.0;
  static const double cardElevationHovered = 2.0;
  static const double cardElevationPressed = 0.0;
}
