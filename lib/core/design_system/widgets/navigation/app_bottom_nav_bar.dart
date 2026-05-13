import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Bottom navigation bar widget with Material Design 3 styling.
/// 
/// Features:
/// - Customizable items
/// - RTL support
/// - Label visibility options
/// 
/// Example:
/// ```dart
/// AppBottomNavBar(
///   currentIndex: 0,
///   onTap: (index) => navigateToPage(index),
///   items: [
///     AppBottomNavItem(icon: Icons.home, label: 'Home'),
///     AppBottomNavItem(icon: Icons.search, label: 'Search'),
///   ],
/// )
/// ```
class AppBottomNavBar extends StatelessWidget {
  /// Currently selected index.
  final int currentIndex;

  /// Callback when item is tapped.
  final ValueChanged<int> onTap;

  /// Navigation items.
  final List<AppBottomNavItem> items;

  /// Background color.
  final Color? backgroundColor;

  /// Selected item color.
  final Color? selectedItemColor;

  /// Unselected item color.
  final Color? unselectedItemColor;

  /// Elevation.
  final double? elevation;

  /// Label type.
  final BottomNavigationBarType? type;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.backgroundColor,
    this.selectedItemColor,
    this.unselectedItemColor,
    this.elevation,
    this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveBackgroundColor = backgroundColor ?? colors.surface;
    final effectiveSelectedItemColor = selectedItemColor ?? colors.primary;
    final effectiveUnselectedItemColor = unselectedItemColor ?? AppColors.textTertiary;
    final effectiveElevation = elevation ?? AppConstants.elevation8;
    final effectiveType = type ?? BottomNavigationBarType.fixed;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: effectiveElevation,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: effectiveBackgroundColor,
        selectedItemColor: effectiveSelectedItemColor,
        unselectedItemColor: effectiveUnselectedItemColor,
        type: effectiveType,
        elevation: 0,
        items: items
            .map((item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  activeIcon: item.activeIcon != null
                      ? Icon(item.activeIcon!)
                      : Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
        selectedLabelStyle: AppTextStyles.labelSmall.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTextStyles.labelSmall,
      ),
    );
  }
}

/// Navigation item for [AppBottomNavBar].
class AppBottomNavItem {
  /// Icon to display.
  final IconData icon;

  /// Icon to display when selected.
  final IconData? activeIcon;

  /// Label text.
  final String label;

  const AppBottomNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}
