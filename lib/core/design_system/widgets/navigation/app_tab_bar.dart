import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Tab bar widget for top navigation with Material Design 3 styling.
/// 
/// Features:
/// - Customizable tabs
/// - RTL support
/// - Indicator customization
/// 
/// Example:
/// ```dart
/// AppTabBar(
///   controller: tabController,
///   tabs: [
///     Tab(text: 'Tab 1'),
///     Tab(text: 'Tab 2'),
///   ],
/// )
/// ```
class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  /// Tab controller.
  final TabController? controller;

  /// List of tabs.
  final List<Widget> tabs;

  /// Callback when tab is tapped.
  final ValueChanged<int>? onTap;

  /// Whether tabs are scrollable.
  final bool isScrollable;

  /// Indicator color.
  final Color? indicatorColor;

  /// Label color.
  final Color? labelColor;

  /// Unselected label color.
  final Color? unselectedLabelColor;

  /// Indicator weight.
  final double? indicatorWeight;

  /// Tab bar padding.
  final EdgeInsetsGeometry? padding;

  const AppTabBar({
    super.key,
    this.controller,
    required this.tabs,
    this.onTap,
    this.isScrollable = false,
    this.indicatorColor,
    this.labelColor,
    this.unselectedLabelColor,
    this.indicatorWeight,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveIndicatorColor = indicatorColor ?? colors.primary;
    final effectiveLabelColor = labelColor ?? colors.primary;
    final effectiveUnselectedLabelColor = unselectedLabelColor ?? AppColors.textTertiary;
    final effectiveIndicatorWeight = indicatorWeight ?? 3.0;
    final effectivePadding = padding ?? AppSpacing.symmetric(
      horizontal: AppSpacing.horizontalLarge,
    );

    return Container(
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.grey200,
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: controller,
        onTap: onTap,
        isScrollable: isScrollable,
        indicatorColor: effectiveIndicatorColor,
        labelColor: effectiveLabelColor,
        unselectedLabelColor: effectiveUnselectedLabelColor,
        indicatorWeight: effectiveIndicatorWeight,
        tabs: tabs,
        labelStyle: AppTextStyles.labelLarge.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTextStyles.labelLarge,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
