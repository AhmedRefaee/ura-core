import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Error display widget with retry functionality.
/// 
/// Features:
/// - Error message and description
/// - Retry button
/// - Customizable icon
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppErrorView(
///   title: 'Error',
///   message: 'Failed to load data',
///   onRetry: () => loadData(),
/// )
/// ```
class AppErrorView extends StatelessWidget {
  /// Error title.
  final String title;

  /// Error message.
  final String? message;

  /// Callback when retry button is pressed.
  final VoidCallback? onRetry;

  /// Retry button text.
  final String? retryText;

  /// Custom error icon.
  final IconData? icon;

  /// Error view padding.
  final EdgeInsetsGeometry? padding;

  const AppErrorView({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.retryText,
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
              icon ?? Icons.error_outline,
              size: AppConstants.iconSizeXLarge,
              color: AppColors.error,
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
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.verticalLarge),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(retryText ?? 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
