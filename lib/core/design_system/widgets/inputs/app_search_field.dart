import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Search input field with clear button.
/// 
/// Features:
/// - Built-in clear button
/// - Search icon
/// - Real-time filtering
/// - RTL support
/// 
/// Example:
/// ```dart
/// AppSearchField(
///   hintText: 'Search items...',
///   onChanged: (query) => filterItems(query),
/// )
/// ```
class AppSearchField extends StatefulWidget {
  /// Placeholder text.
  final String? hintText;

  /// Current search query.
  final String? initialValue;

  /// Callback when search query changes.
  final ValueChanged<String>? onChanged;

  /// Callback when search is submitted.
  final ValueChanged<String>? onSubmitted;

  /// Whether field is enabled.
  final bool enabled;

  /// Field height.
  final double? height;

  const AppSearchField({
    super.key,
    this.hintText,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.height,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasText = _controller.text.isNotEmpty;
    });
    widget.onChanged?.call(_controller.text);
  }

  void _clearText() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height ?? AppConstants.inputFieldHeightSmall;

    return SizedBox(
      height: effectiveHeight,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        enabled: widget.enabled,
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: widget.hintText ?? 'Search...',
          hintStyle: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textTertiary,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.textTertiary,
          ),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: _clearText,
                )
              : null,
          filled: true,
          fillColor: widget.enabled
              ? AppColors.white
              : AppColors.grey100,
          contentPadding: AppSpacing.horizontalLargePadding,
          border: OutlineInputBorder(
            borderRadius: AppConstants.borderRadiusSmallRadius,
            borderSide: const BorderSide(color: AppColors.grey300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppConstants.borderRadiusSmallRadius,
            borderSide: const BorderSide(color: AppColors.grey300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppConstants.borderRadiusSmallRadius,
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: AppConstants.borderRadiusSmallRadius,
            borderSide: const BorderSide(color: AppColors.grey200),
          ),
        ),
      ),
    );
  }
}
