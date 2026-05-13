import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Custom snackbar variants for displaying messages.
/// 
/// Features:
/// - Multiple variants (success, error, warning, info)
/// - Action button support
/// - Dismissible
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppSnackbar.show(
///   context: context,
///   message: 'Item deleted successfully',
///   variant: AppSnackbarVariant.success,
/// )
/// ```
class AppSnackbar {
  /// Show a snackbar with the specified parameters.
  static void show(
    BuildContext context, {
    required String message,
    AppSnackbarVariant variant = AppSnackbarVariant.info,
    String? actionText,
    VoidCallback? onActionPressed,
    Duration duration = const Duration(seconds: 4),
    bool showCloseIcon = false,
    SnackBarAction? action,
  }) {
    final config = _getSnackbarConfig(variant);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(config.icon, color: AppColors.white),
            const SizedBox(width: AppSpacing.horizontalMedium),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: config.backgroundColor,
        duration: duration,
        action: action ??
            (actionText != null && onActionPressed != null
                ? SnackBarAction(
                    label: actionText,
                    textColor: AppColors.white,
                    onPressed: onActionPressed,
                  )
                : null),
        showCloseIcon: showCloseIcon,
        closeIconColor: AppColors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppConstants.borderRadiusSmallRadius,
        ),
        margin: AppSpacing.allMedium,
      ),
    );
  }

  static _SnackbarConfig _getSnackbarConfig(AppSnackbarVariant variant) {
    switch (variant) {
      case AppSnackbarVariant.success:
        return _SnackbarConfig(
          backgroundColor: AppColors.success,
          icon: Icons.check_circle,
        );
      case AppSnackbarVariant.error:
        return _SnackbarConfig(
          backgroundColor: AppColors.error,
          icon: Icons.error,
        );
      case AppSnackbarVariant.warning:
        return _SnackbarConfig(
          backgroundColor: AppColors.warning,
          icon: Icons.warning,
        );
      case AppSnackbarVariant.info:
        return _SnackbarConfig(
          backgroundColor: AppColors.info,
          icon: Icons.info,
        );
    }
  }
}

/// Snackbar variants for [AppSnackbar].
enum AppSnackbarVariant {
  /// Success snackbar
  success,

  /// Error snackbar
  error,

  /// Warning snackbar
  warning,

  /// Info snackbar
  info,
}

class _SnackbarConfig {
  final Color backgroundColor;
  final IconData icon;

  const _SnackbarConfig({
    required this.backgroundColor,
    required this.icon,
  });
}
