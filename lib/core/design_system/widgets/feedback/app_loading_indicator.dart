import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Loading spinner widget with customizable styling.
/// 
/// Features:
/// - Customizable size and color
/// - Optional background overlay
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppLoadingIndicator(
///   size: 48,
///   color: AppColors.primary,
/// )
/// ```
class AppLoadingIndicator extends StatelessWidget {
  /// Indicator size.
  final double? size;

  /// Indicator color.
  final Color? color;

  /// Stroke width.
  final double? strokeWidth;

  /// Whether to show background overlay.
  final bool showOverlay;

  const AppLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.showOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveColor = color ?? colors.primary;
    final effectiveSize = size ?? AppConstants.iconSizeLarge;
    final effectiveStrokeWidth = strokeWidth ?? 3.0;

    Widget indicator = SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
        strokeWidth: effectiveStrokeWidth,
      ),
    );

    if (showOverlay) {
      indicator = Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(child: indicator),
      );
    }

    return indicator;
  }
}
