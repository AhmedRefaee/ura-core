import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Loading state indicator widget.
/// 
/// Features:
/// - Customizable message
/// - Progress indicator
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppLoadingState(
///   message: 'Loading data...',
/// )
/// ```
class AppLoadingState extends StatelessWidget {
  /// Loading message.
  final String? message;

  /// Whether to show circular progress indicator.
  final bool showCircularIndicator;

  /// Custom loading widget.
  final Widget? customWidget;

  /// Loading state padding.
  final EdgeInsetsGeometry? padding;

  const AppLoadingState({
    super.key,
    this.message,
    this.showCircularIndicator = true,
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
            else if (showCircularIndicator)
              const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.verticalLarge),
              Text(
                message!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
