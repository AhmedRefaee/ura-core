import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Section widget with title and content.
/// 
/// Features:
/// - Optional title and subtitle
/// - Customizable padding
/// - RTL support
/// - Action button support
/// 
/// Example:
/// ```dart
/// AppSection(
///   title: 'Personal Information',
///   child: Column(
///     children: [
///       Text('Name: John Doe'),
///       Text('Email: john@example.com'),
///     ],
///   ),
/// )
/// ```
class AppSection extends StatelessWidget {
  /// Section title.
  final String? title;

  /// Section subtitle.
  final String? subtitle;

  /// Section content.
  final Widget child;

  /// Action button text.
  final String? actionText;

  /// Callback when action button is pressed.
  final VoidCallback? onActionPressed;

  /// Section padding.
  final EdgeInsetsGeometry? padding;

  /// Section margin.
  final EdgeInsetsGeometry? margin;

  /// Whether to show divider at bottom.
  final bool showDivider;

  /// Whether to show divider at top.
  final bool showTopDivider;

  const AppSection({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.actionText,
    this.onActionPressed,
    this.padding,
    this.margin,
    this.showDivider = false,
    this.showTopDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? AppSpacing.allMedium;
    final effectiveMargin = margin ?? EdgeInsets.only(
      bottom: AppSpacing.verticalLarge,
    );

    return Container(
      margin: effectiveMargin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTopDivider)
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.grey200,
            ),
          if (title != null || subtitle != null) ...[
            Padding(
              padding: AppSpacing.symmetric(
                horizontal: AppSpacing.horizontalLarge,
                vertical: AppSpacing.verticalSmall,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.verticalXSmall),
                          Text(
                            subtitle!,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actionText != null && onActionPressed != null) ...[
                    const SizedBox(width: AppSpacing.horizontalMedium),
                    TextButton(
                      onPressed: onActionPressed,
                      child: Text(
                        actionText!,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.verticalSmall),
          ],
          Padding(
            padding: effectivePadding,
            child: child,
          ),
          if (showDivider)
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.grey200,
            ),
        ],
      ),
    );
  }
}
