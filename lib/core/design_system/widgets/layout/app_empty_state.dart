import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Empty state placeholder widget.
/// 
/// Features:
/// - Icon support
/// - Customizable message and description
/// - Action button support
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppEmptyState(
///   icon: Icons.inbox,
///   title: 'No Items',
///   description: 'There are no items to display',
///   actionText: 'Create Item',
///   onActionPressed: () => createNewItem(),
/// )
/// ```
class AppEmptyState extends StatelessWidget {
  /// Icon to display.
  final IconData? icon;

  /// Empty state title.
  final String title;

  /// Empty state description.
  final String? description;

  /// Action button text.
  final String? actionText;

  /// Callback when action button is pressed.
  final VoidCallback? onActionPressed;

  /// Custom widget to display instead of icon.
  final Widget? customWidget;

  /// Empty state padding.
  final EdgeInsetsGeometry? padding;

  const AppEmptyState({
    super.key,
    this.icon,
    required this.title,
    this.description,
    this.actionText,
    this.onActionPressed,
    this.customWidget,
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
            if (customWidget != null)
              customWidget!
            else if (icon != null)
              Icon(
                icon,
                size: AppConstants.iconSizeXLarge,
                color: AppColors.grey400,
              ),
            const SizedBox(height: AppSpacing.verticalLarge),
            Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.verticalSmall),
              Text(
                description!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
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
