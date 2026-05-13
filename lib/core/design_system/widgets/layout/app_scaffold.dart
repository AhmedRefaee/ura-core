import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Scaffold with consistent structure and styling.
/// 
/// Features:
/// - Consistent padding
/// - Safe area handling
/// - RTL support
/// - Customizable app bar
/// - Bottom navigation support
/// 
/// Example:
/// ```dart
/// AppScaffold(
///   appBar: AppBar(title: Text('Home')),
///   body: Center(child: Text('Content')),
/// )
/// ```
class AppScaffold extends StatelessWidget {
  /// App bar widget.
  final PreferredSizeWidget? appBar;

  /// Body content.
  final Widget body;

  /// Bottom navigation bar.
  final Widget? bottomNavigationBar;

  /// Floating action button.
  final Widget? floatingActionButton;

  /// Floating action button location.
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// Whether to resize to avoid bottom inset.
  final bool resizeToAvoidBottomInset;

  /// Background color.
  final Color? backgroundColor;

  /// Whether to show safe area.
  final bool useSafeArea;

  /// Scaffold padding.
  final EdgeInsetsGeometry? padding;

  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.useSafeArea = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBackgroundColor = backgroundColor ?? AppColors.background;
    final effectivePadding = padding ?? AppSpacing.screenPaddingInsets;

    Widget scaffoldBody = body;

    if (padding != null) {
      scaffoldBody = Padding(
        padding: effectivePadding,
        child: body,
      );
    }

    Widget scaffold = Scaffold(
      appBar: appBar,
      body: scaffoldBody,
      backgroundColor: effectiveBackgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );

    if (useSafeArea) {
      scaffold = SafeArea(child: scaffold);
    }

    return scaffold;
  }
}
