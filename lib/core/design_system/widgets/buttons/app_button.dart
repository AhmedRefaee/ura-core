import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Primary button widget with multiple variants.
/// 
/// Supports three variants:
/// - [AppButtonVariant.elevated]: Filled button with shadow
/// - [AppButtonVariant.outlined]: Button with border
/// - [AppButtonVariant.text]: Text-only button
/// 
/// Example:
/// ```dart
/// AppButton(
///   text: 'Submit',
///   onPressed: () {},
///   variant: AppButtonVariant.elevated,
/// )
/// ```
class AppButton extends StatelessWidget {
  /// The text to display on the button.
  final String text;

  /// Callback when the button is pressed.
  final VoidCallback? onPressed;

  /// The button variant to use.
  final AppButtonVariant variant;

  /// Whether the button is in loading state.
  final bool isLoading;

  /// Whether the button is disabled.
  final bool isDisabled;

  /// The button width. If null, uses intrinsic width.
  final double? width;

  /// The button height. Defaults to [AppConstants.buttonHeight].
  final double? height;

  /// The icon to display before the text.
  final IconData? icon;

  /// The button's background color.
  final Color? backgroundColor;

  /// The text color.
  final Color? textColor;

  /// The border radius.
  final BorderRadius? borderRadius;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.elevated,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.height,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveBackgroundColor = backgroundColor ?? colors.primary;
    final effectiveTextColor = textColor ?? AppColors.textOnPrimary;
    final effectiveBorderRadius = borderRadius ?? AppConstants.borderRadiusSmallRadius;
    final effectiveHeight = height ?? AppConstants.buttonHeight;
    final isDisabledState = isDisabled || isLoading || onPressed == null;

    Widget buttonChild() {
      if (isLoading) {
        return SizedBox(
          height: effectiveHeight,
          width: effectiveHeight,
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      }

      if (icon != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppConstants.iconSizeMedium),
            const SizedBox(width: AppSpacing.horizontalSmall),
            Text(text),
          ],
        );
      }

      return Text(text);
    }

    return SizedBox(
      width: width,
      height: effectiveHeight,
      child: _buildButton(
        context,
        effectiveBackgroundColor,
        effectiveTextColor,
        effectiveBorderRadius,
        isDisabledState,
        buttonChild,
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    Color backgroundColor,
    Color textColor,
    BorderRadius borderRadius,
    bool isDisabledState,
    Widget Function() childBuilder,
  ) {
    switch (variant) {
      case AppButtonVariant.elevated:
        return ElevatedButton(
          onPressed: isDisabledState ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDisabledState ? AppColors.grey400 : backgroundColor,
            foregroundColor: textColor,
            disabledBackgroundColor: AppColors.grey400,
            disabledForegroundColor: AppColors.textDisabled,
            elevation: AppConstants.elevation2,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
            ),
            padding: AppSpacing.horizontalLargePadding,
          ),
          child: childBuilder(),
        );

      case AppButtonVariant.outlined:
        return OutlinedButton(
          onPressed: isDisabledState ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: isDisabledState ? AppColors.textDisabled : backgroundColor,
            disabledForegroundColor: AppColors.textDisabled,
            side: BorderSide(
              color: isDisabledState ? AppColors.grey400 : backgroundColor,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
            ),
            padding: AppSpacing.horizontalLargePadding,
          ),
          child: childBuilder(),
        );

      case AppButtonVariant.text:
        return TextButton(
          onPressed: isDisabledState ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: isDisabledState ? AppColors.textDisabled : backgroundColor,
            disabledForegroundColor: AppColors.textDisabled,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
            ),
            padding: AppSpacing.horizontalLargePadding,
          ),
          child: childBuilder(),
        );
    }
  }
}

/// Button variants for [AppButton].
enum AppButtonVariant {
  /// Filled button with shadow
  elevated,

  /// Button with border
  outlined,

  /// Text-only button
  text,
}
