import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Back button widget with optional custom action.
/// 
/// Features:
/// - Custom icon
/// - Custom action
/// - RTL support
/// - Tooltip support
/// 
/// Example:
/// ```dart
/// AppBackButton(
///   onPressed: () => Navigator.pop(context),
/// )
/// ```
class AppBackButton extends StatelessWidget {
  /// Callback when button is pressed.
  final VoidCallback? onPressed;

  /// Custom icon.
  final IconData? icon;

  /// Icon color.
  final Color? color;

  /// Icon size.
  final double? iconSize;

  /// Tooltip text.
  final String? tooltip;

  const AppBackButton({
    super.key,
    this.onPressed,
    this.icon,
    this.color,
    this.iconSize,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveColor = color ?? colors.onSurface;
    final effectiveIconSize = iconSize ?? AppConstants.iconSizeMedium;
    final effectiveIcon = icon ?? Icons.arrow_back_ios;

    Widget button = IconButton(
      icon: Icon(
        effectiveIcon,
        color: effectiveColor,
        size: effectiveIconSize,
      ),
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      padding: AppSpacing.allSmall,
      constraints: const BoxConstraints(),
      splashRadius: AppConstants.iconSizeLarge,
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}
