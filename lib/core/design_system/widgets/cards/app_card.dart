import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Basic card widget with elevation and customizable styling.
/// 
/// Features:
/// - Customizable elevation
/// - Border radius options
/// - Color customization
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppCard(
///   child: Text('Card content'),
///   elevation: AppConstants.cardElevation,
///   padding: AppSpacing.allMedium,
/// )
/// ```
class AppCard extends StatelessWidget {
  /// Card content.
  final Widget child;

  /// Card elevation.
  final double? elevation;

  /// Card border radius.
  final BorderRadius? borderRadius;

  /// Card background color.
  final Color? color;

  /// Card padding.
  final EdgeInsetsGeometry? padding;

  /// Card margin.
  final EdgeInsetsGeometry? margin;

  /// Whether card is clickable.
  final bool isClickable;

  /// Callback when card is tapped.
  final VoidCallback? onTap;

  /// Card border.
  final BoxBorder? border;

  /// Card shadow color.
  final Color? shadowColor;

  const AppCard({
    super.key,
    required this.child,
    this.elevation,
    this.borderRadius,
    this.color,
    this.padding,
    this.margin,
    this.isClickable = false,
    this.onTap,
    this.border,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveElevation = elevation ?? AppConstants.cardElevation;
    final effectiveBorderRadius = borderRadius ?? AppConstants.borderRadiusMediumRadius;
    final effectiveColor = color ?? AppColors.white;
    final effectivePadding = padding ?? AppSpacing.allMedium;

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: effectiveBorderRadius,
        border: border,
        boxShadow: [
          BoxShadow(
            color: shadowColor ?? Colors.black.withValues(alpha: 0.1),
            blurRadius: effectiveElevation * 2,
            offset: Offset(0, effectiveElevation),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
    );

    if (isClickable && onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: effectiveBorderRadius,
        child: card,
      );
    }

    return card;
  }
}
