import 'package:flutter/material.dart';

/// Spacing system for URA CORE application.
/// Uses 4-point scale (4, 8, 12, 16, 20, 24, 32) for consistent spacing.
class AppSpacing {
  const AppSpacing._();

  // ========================================
  // Screen Padding
  // ========================================
  static const double screenHorizontal = 24.0;
  static const double screenVertical = 24.0;
  static const double screenPadding = 24.0;

  // ========================================
  // Horizontal Spacing
  // ========================================
  static const double horizontalXSmall = 4.0;
  static const double horizontalSmall = 8.0;
  static const double horizontalMedium = 12.0;
  static const double horizontalLarge = 16.0;
  static const double horizontalXLarge = 20.0;
  static const double horizontalXXLarge = 24.0;
  static const double horizontalXXXLarge = 32.0;

  // ========================================
  // Vertical Spacing
  // ========================================
  static const double verticalXSmall = 4.0;
  static const double verticalSmall = 8.0;
  static const double verticalMedium = 12.0;
  static const double verticalLarge = 16.0;
  static const double verticalXLarge = 20.0;
  static const double verticalXXLarge = 24.0;
  static const double verticalXXXLarge = 32.0;

  // ========================================
  // Edge Insets Helpers
  // ========================================
  static const EdgeInsets allXSmall = EdgeInsets.all(horizontalXSmall);
  static const EdgeInsets allSmall = EdgeInsets.all(horizontalSmall);
  static const EdgeInsets allMedium = EdgeInsets.all(horizontalMedium);
  static const EdgeInsets allLarge = EdgeInsets.all(horizontalLarge);
  static const EdgeInsets allXLarge = EdgeInsets.all(horizontalXLarge);
  static const EdgeInsets allXXLarge = EdgeInsets.all(horizontalXXLarge);
  static const EdgeInsets allXXXLarge = EdgeInsets.all(horizontalXXXLarge);

  static const EdgeInsets horizontalXSmallPadding =
      EdgeInsets.symmetric(horizontal: horizontalXSmall);
  static const EdgeInsets horizontalSmallPadding =
      EdgeInsets.symmetric(horizontal: horizontalSmall);
  static const EdgeInsets horizontalMediumPadding =
      EdgeInsets.symmetric(horizontal: horizontalMedium);
  static const EdgeInsets horizontalLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalLarge);
  static const EdgeInsets horizontalXLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalXLarge);
  static const EdgeInsets horizontalXXLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalXXLarge);
  static const EdgeInsets horizontalXXXLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalXXXLarge);

  static const EdgeInsets verticalXSmallPadding =
      EdgeInsets.symmetric(vertical: verticalXSmall);
  static const EdgeInsets verticalSmallPadding =
      EdgeInsets.symmetric(vertical: verticalSmall);
  static const EdgeInsets verticalMediumPadding =
      EdgeInsets.symmetric(vertical: verticalMedium);
  static const EdgeInsets verticalLargePadding =
      EdgeInsets.symmetric(vertical: verticalLarge);
  static const EdgeInsets verticalXLargePadding =
      EdgeInsets.symmetric(vertical: verticalXLarge);
  static const EdgeInsets verticalXXLargePadding =
      EdgeInsets.symmetric(vertical: verticalXXLarge);
  static const EdgeInsets verticalXXXLargePadding =
      EdgeInsets.symmetric(vertical: verticalXXXLarge);

  static const EdgeInsets screenPaddingInsets =
      EdgeInsets.symmetric(horizontal: screenHorizontal, vertical: screenVertical);

  // ========================================
  // Custom Edge Insets Helpers
  // ========================================
  static EdgeInsets only({
    double left = 0.0,
    double top = 0.0,
    double right = 0.0,
    double bottom = 0.0,
  }) {
    return EdgeInsets.only(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  static EdgeInsets symmetric({
    double horizontal = 0.0,
    double vertical = 0.0,
  }) {
    return EdgeInsets.symmetric(
      horizontal: horizontal,
      vertical: vertical,
    );
  }
}
