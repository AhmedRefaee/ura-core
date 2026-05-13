import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Floating action button widget with multiple variants.
/// 
/// Supports standard and extended FABs with optional labels.
/// 
/// Example:
/// ```dart
/// AppFloatingActionButton(
///   icon: Icons.add,
///   onPressed: () {},
///   label: 'Add Item',
/// )
/// ```
class AppFloatingActionButton extends StatelessWidget {
  /// The icon to display.
  final IconData icon;

  /// Callback when the button is pressed.
  final VoidCallback? onPressed;

  /// Optional label text for extended FAB.
  final String? label;

  /// The button's background color.
  final Color? backgroundColor;

  /// The icon color.
  final Color? iconColor;

  /// The label text style.
  final TextStyle? labelStyle;

  /// Whether to show extended FAB.
  final bool isExtended;

  /// The FAB size.
  final double? size;

  const AppFloatingActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.backgroundColor,
    this.iconColor,
    this.labelStyle,
    this.isExtended = false,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveBackgroundColor = backgroundColor ?? colors.primary;
    final effectiveIconColor = iconColor ?? AppColors.textOnPrimary;
    final effectiveLabelStyle = labelStyle ?? AppTextStyles.labelLarge;

    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: effectiveBackgroundColor,
        foregroundColor: effectiveIconColor,
        elevation: AppConstants.elevation6,
        icon: Icon(icon),
        label: Text(
          label!,
          style: effectiveLabelStyle.copyWith(color: effectiveIconColor),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: effectiveBackgroundColor,
        foregroundColor: effectiveIconColor,
        elevation: AppConstants.elevation6,
        child: Icon(icon),
      ),
    );
  }
}
