import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Icon button widget with multiple variants.
/// 
/// Supports three variants:
/// - [AppIconButtonVariant.filled]: Filled icon button
/// - [AppIconButtonVariant.outlined]: Outlined icon button
/// - [AppIconButtonVariant.text]: Text-only icon button
/// 
/// Example:
/// ```dart
/// AppIconButton(
///   icon: Icons.add,
///   onPressed: () {},
///   variant: AppIconButtonVariant.filled,
/// )
/// ```
class AppIconButton extends StatelessWidget {
  /// The icon to display.
  final IconData icon;

  /// Callback when the button is pressed.
  final VoidCallback? onPressed;

  /// The button variant to use.
  final AppIconButtonVariant variant;

  /// The button size. Defaults to [AppConstants.buttonHeight].
  final double? size;

  /// The icon size. Defaults to [AppConstants.iconSizeMedium].
  final double? iconSize;

  /// The button's background color.
  final Color? backgroundColor;

  /// The icon color.
  final Color? iconColor;

  /// The border radius.
  final BorderRadius? borderRadius;

  /// Tooltip text for accessibility.
  final String? tooltip;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.variant = AppIconButtonVariant.filled,
    this.size,
    this.iconSize,
    this.backgroundColor,
    this.iconColor,
    this.borderRadius,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveBackgroundColor = backgroundColor ?? colors.primary;
    final effectiveIconColor = iconColor ?? AppColors.textOnPrimary;
    final effectiveBorderRadius = borderRadius ?? AppConstants.borderRadiusSmallRadius;
    final effectiveSize = size ?? AppConstants.buttonHeight;
    final effectiveIconSize = iconSize ?? AppConstants.iconSizeMedium;
    final isDisabled = onPressed == null;

    Widget button = SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: _buildButton(
        context,
        effectiveBackgroundColor,
        effectiveIconColor,
        effectiveBorderRadius,
        isDisabled,
        effectiveIconSize,
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }

  Widget _buildButton(
    BuildContext context,
    Color backgroundColor,
    Color iconColor,
    BorderRadius borderRadius,
    bool isDisabled,
    double effectiveIconSize,
  ) {
    switch (variant) {
      case AppIconButtonVariant.filled:
        return Material(
          color: isDisabled ? AppColors.grey400 : backgroundColor,
          borderRadius: borderRadius,
          elevation: isDisabled ? 0 : AppConstants.elevation2,
          child: InkWell(
            onTap: isDisabled ? null : onPressed,
            borderRadius: borderRadius,
            child: Center(
              child: Icon(
                icon,
                size: effectiveIconSize,
                color: isDisabled ? AppColors.textDisabled : iconColor,
              ),
            ),
          ),
        );

      case AppIconButtonVariant.outlined:
        return Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: isDisabled ? null : onPressed,
            borderRadius: borderRadius,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDisabled ? AppColors.grey400 : backgroundColor,
                  width: 1.5,
                ),
                borderRadius: borderRadius,
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: effectiveIconSize,
                  color: isDisabled ? AppColors.textDisabled : backgroundColor,
                ),
              ),
            ),
          ),
        );

      case AppIconButtonVariant.text:
        return Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: isDisabled ? null : onPressed,
            borderRadius: borderRadius,
            child: Center(
              child: Icon(
                icon,
                size: effectiveIconSize,
                color: isDisabled ? AppColors.textDisabled : backgroundColor,
              ),
            ),
          ),
        );
    }
  }
}

/// Icon button variants for [AppIconButton].
enum AppIconButtonVariant {
  /// Filled icon button
  filled,

  /// Outlined icon button
  outlined,

  /// Text-only icon button
  text,
}
