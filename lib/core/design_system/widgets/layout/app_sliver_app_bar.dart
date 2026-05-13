import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Custom app bar with scroll behavior and Material Design 3 styling.
/// 
/// Features:
/// - Scroll behavior
/// - Customizable actions
/// - RTL support
/// - Flexible space support
/// 
/// Example:
/// ```dart
/// AppSliverAppBar(
///   title: 'My Page',
///   actions: [
///     IconButton(icon: Icon(Icons.search), onPressed: () {}),
///   ],
/// )
/// ```
class AppSliverAppBar extends StatelessWidget {
  /// App bar title.
  final String? title;

  /// Custom title widget.
  final Widget? titleWidget;

  /// Action buttons.
  final List<Widget>? actions;

  /// Leading widget (usually back button or menu).
  final Widget? leading;

  /// Whether to automatically add back button.
  final bool automaticallyImplyLeading;

  /// Whether app bar should float.
  final bool floating;

  /// Whether app bar should snap.
  final bool snap;

  /// Whether app bar should be pinned.
  final bool pinned;

  /// App bar elevation.
  final double? elevation;

  /// App bar background color.
  final Color? backgroundColor;

  /// App bar foreground color.
  final Color? foregroundColor;

  /// Flexible space widget.
  final Widget? flexibleSpace;

  /// Bottom widget (usually TabBar).
  final PreferredSizeWidget? bottom;

  /// App bar height.
  final double? expandedHeight;

  const AppSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.floating = false,
    this.snap = false,
    this.pinned = true,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.flexibleSpace,
    this.bottom,
    this.expandedHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveBackgroundColor = backgroundColor ?? colors.surface;
    final effectiveForegroundColor = foregroundColor ?? colors.onSurface;
    final effectiveElevation = elevation ?? AppConstants.elevation2;

    return SliverAppBar(
      title: titleWidget ?? (title != null ? Text(title!) : null),
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      floating: floating,
      snap: snap,
      pinned: pinned,
      elevation: effectiveElevation,
      backgroundColor: effectiveBackgroundColor,
      foregroundColor: effectiveForegroundColor,
      flexibleSpace: flexibleSpace,
      bottom: bottom,
      expandedHeight: expandedHeight,
      centerTitle: true,
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: effectiveForegroundColor,
      ),
      iconTheme: IconThemeData(color: effectiveForegroundColor),
      actionsIconTheme: IconThemeData(color: effectiveForegroundColor),
    );
  }
}
