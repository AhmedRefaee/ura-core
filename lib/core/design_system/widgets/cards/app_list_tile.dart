import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// List tile widget with leading, title, subtitle, and trailing widgets.
/// 
/// Features:
/// - Customizable leading/trailing widgets
/// - Three-line support
/// - RTL support
/// - Tap handling
/// 
/// Example:
/// ```dart
/// AppListTile(
///   leading: Icon(Icons.person),
///   title: 'John Doe',
///   subtitle: 'Software Engineer',
///   trailing: Icon(Icons.arrow_forward_ios),
///   onTap: () => navigateToDetail(),
/// )
/// ```
class AppListTile extends StatelessWidget {
  /// Leading widget (usually an icon or avatar).
  final Widget? leading;

  /// Title text or widget.
  final Widget title;

  /// Optional subtitle text or widget.
  final Widget? subtitle;

  /// Trailing widget (usually an icon or button).
  final Widget? trailing;

  /// Callback when tile is tapped.
  final VoidCallback? onTap;

  /// Callback when tile is long-pressed.
  final VoidCallback? onLongPress;

  /// Whether to show three lines (title + 2 subtitle lines).
  final bool isThreeLine;

  /// Whether tile is dense (less vertical padding).
  final bool isDense;

  /// Tile content padding.
  final EdgeInsetsGeometry? contentPadding;

  /// Tile background color.
  final Color? backgroundColor;

  /// Whether to show divider at bottom.
  final bool showDivider;

  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.isThreeLine = false,
    this.isDense = false,
    this.contentPadding,
    this.backgroundColor,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveContentPadding = contentPadding ??
        AppSpacing.horizontalLargePadding.copyWith(
          top: AppSpacing.verticalMedium,
          bottom: AppSpacing.verticalMedium,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor ?? Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: effectiveContentPadding,
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppSpacing.horizontalMedium),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DefaultTextStyle(
                          style: AppTextStyles.titleMedium.copyWith(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          child: title,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.verticalXSmall),
                          DefaultTextStyle(
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                            ),
                            maxLines: isThreeLine ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.horizontalMedium),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.grey200,
          ),
      ],
    );
  }
}
