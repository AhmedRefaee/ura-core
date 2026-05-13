import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Information display card with icon, title, and description.
/// 
/// Features:
/// - Status-based coloring (success, error, warning, info)
/// - Icon support
/// - Action button support
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppInfoCard(
///   status: AppInfoCardStatus.success,
///   icon: Icons.check_circle,
///   title: 'Success',
///   description: 'Operation completed successfully',
/// )
/// ```
class AppInfoCard extends StatelessWidget {
  /// Card status type.
  final AppInfoCardStatus status;

  /// Icon to display.
  final IconData? icon;

  /// Card title.
  final String title;

  /// Card description.
  final String? description;

  /// Action button text.
  final String? actionText;

  /// Callback when action button is pressed.
  final VoidCallback? onActionPressed;

  /// Card padding.
  final EdgeInsetsGeometry? padding;

  /// Whether card is dismissible.
  final bool isDismissible;

  /// Callback when dismiss button is pressed.
  final VoidCallback? onDismissed;

  const AppInfoCard({
    super.key,
    required this.status,
    this.icon,
    required this.title,
    this.description,
    this.actionText,
    this.onActionPressed,
    this.padding,
    this.isDismissible = false,
    this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    
    final statusConfig = _getStatusConfig();
    final effectivePadding = padding ?? AppSpacing.allMedium;

    return Container(
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: statusConfig.backgroundColor,
        borderRadius: AppConstants.borderRadiusMediumRadius,
        border: Border.all(
          color: statusConfig.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              icon ?? statusConfig.defaultIcon,
              color: statusConfig.iconColor,
              size: AppConstants.iconSizeLarge,
            ),
            const SizedBox(width: AppSpacing.horizontalMedium),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: statusConfig.textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isDismissible && onDismissed != null) ...[
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: statusConfig.iconColor,
                          size: AppConstants.iconSizeSmall,
                        ),
                        onPressed: onDismissed,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: AppSpacing.verticalXSmall),
                  Text(
                    description!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: statusConfig.textColor,
                    ),
                  ),
                ],
                if (actionText != null && onActionPressed != null) ...[
                  const SizedBox(height: AppSpacing.verticalSmall),
                  TextButton(
                    onPressed: onActionPressed,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      actionText!,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: statusConfig.iconColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _InfoCardConfig _getStatusConfig() {
    switch (status) {
      case AppInfoCardStatus.success:
        return _InfoCardConfig(
          backgroundColor: AppColors.successLight,
          borderColor: AppColors.success,
          iconColor: AppColors.success,
          textColor: AppColors.successDark,
          defaultIcon: Icons.check_circle,
        );
      case AppInfoCardStatus.error:
        return _InfoCardConfig(
          backgroundColor: AppColors.errorLight,
          borderColor: AppColors.error,
          iconColor: AppColors.error,
          textColor: AppColors.errorDark,
          defaultIcon: Icons.error,
        );
      case AppInfoCardStatus.warning:
        return _InfoCardConfig(
          backgroundColor: AppColors.warningLight,
          borderColor: AppColors.warning,
          iconColor: AppColors.warning,
          textColor: AppColors.warningDark,
          defaultIcon: Icons.warning,
        );
      case AppInfoCardStatus.info:
        return _InfoCardConfig(
          backgroundColor: AppColors.infoLight,
          borderColor: AppColors.info,
          iconColor: AppColors.info,
          textColor: AppColors.infoDark,
          defaultIcon: Icons.info,
        );
    }
  }
}

/// Status types for [AppInfoCard].
enum AppInfoCardStatus {
  /// Success status
  success,

  /// Error status
  error,

  /// Warning status
  warning,

  /// Info status
  info,
}

class _InfoCardConfig {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;
  final IconData defaultIcon;

  const _InfoCardConfig({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
    required this.defaultIcon,
  });
}
