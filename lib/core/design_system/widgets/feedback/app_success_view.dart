import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Success message display widget.
/// 
/// Features:
/// - Success message and description
/// - Action button support
/// - Customizable icon
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppSuccessView(
///   title: 'Success',
///   message: 'Operation completed successfully',
///   actionText: 'Continue',
///   onActionPressed: () => navigateNext(),
/// )
/// ```
class AppSuccessView extends StatelessWidget {
  /// Success title.
  final String title;

  /// Success message.
  final String? message;

  /// Action button text.
  final String? actionText;

  /// Callback when action button is pressed.
  final VoidCallback? onActionPressed;

  /// Custom success icon.
  final IconData? icon;

  /// Success view padding.
  final EdgeInsetsGeometry? padding;

  const AppSuccessView({
    super.key,
    required this.title,
    this.message,
    this.actionText,
    this.onActionPressed,
    this.icon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? AppSpacing.allXXLarge;

    return Padding(
      padding: effectivePadding,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.check_circle_outline,
              size: AppConstants.iconSizeXLarge,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpacing.verticalLarge),
            Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.verticalSmall),
              Text(
                message!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionText != null && onActionPressed != null) ...[
              const SizedBox(height: AppSpacing.verticalLarge),
              ElevatedButton(
                onPressed: onActionPressed,
                child: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
