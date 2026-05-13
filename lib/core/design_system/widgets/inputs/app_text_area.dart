import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme.dart';

/// Multi-line text input area.
/// 
/// Features:
/// - Character counter
/// - Validation support
/// - RTL support
/// - Customizable height
/// 
/// Example:
/// ```dart
/// AppTextArea(
///   label: 'Description',
///   hintText: 'Enter description...',
///   maxLines: 5,
///   maxLength: 500,
///   showCounter: true,
///   validator: (value) => value!.isEmpty ? 'Required' : null,
/// )
/// ```
class AppTextArea extends StatefulWidget {
  /// Field label displayed above the input.
  final String? label;

  /// Placeholder text when field is empty.
  final String? hintText;

  /// Current text value.
  final String? initialValue;

  /// Callback when text changes.
  final ValueChanged<String>? onChanged;

  /// Validation function.
  final FormFieldValidator<String>? validator;

  /// Maximum number of lines.
  final int maxLines;

  /// Minimum number of lines.
  final int minLines;

  /// Maximum number of characters.
  final int? maxLength;

  /// Whether to show character counter.
  final bool showCounter;

  /// Whether field is required.
  final bool isRequired;

  /// Whether field is read-only.
  final bool readOnly;

  /// Whether field is enabled.
  final bool enabled;

  /// Input formatters.
  final List<TextInputFormatter>? inputFormatters;

  /// Text editing controller.
  final TextEditingController? controller;

  /// Focus node.
  final FocusNode? focusNode;

  /// Text style.
  final TextStyle? textStyle;

  /// Label text style.
  final TextStyle? labelStyle;

  /// Hint text style.
  final TextStyle? hintStyle;

  /// Border radius.
  final BorderRadius? borderRadius;

  const AppTextArea({
    super.key,
    this.label,
    this.hintText,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.maxLines = 5,
    this.minLines = 3,
    this.maxLength,
    this.showCounter = false,
    this.isRequired = false,
    this.readOnly = false,
    this.enabled = true,
    this.inputFormatters,
    this.controller,
    this.focusNode,
    this.textStyle,
    this.labelStyle,
    this.hintStyle,
    this.borderRadius,
  });

  @override
  State<AppTextArea> createState() => _AppTextAreaState();
}

class _AppTextAreaState extends State<AppTextArea> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = widget.borderRadius ?? AppConstants.borderRadiusSmallRadius;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Row(
            children: [
              Text(
                widget.label!,
                style: widget.labelStyle ?? AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.isRequired) ...[
                const SizedBox(width: AppSpacing.horizontalXSmall),
                Text(
                  '*',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.verticalSmall),
        ],
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: widget.onChanged,
          validator: widget.validator,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          readOnly: widget.readOnly,
          enabled: widget.enabled,
          inputFormatters: widget.inputFormatters,
          style: widget.textStyle ?? AppTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: widget.hintStyle ?? AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textTertiary,
            ),
            counterText: widget.showCounter ? null : '',
            filled: true,
            fillColor: widget.enabled
                ? AppColors.white
                : AppColors.grey100,
            contentPadding: AppSpacing.horizontalLargePadding.copyWith(
              top: AppSpacing.verticalMedium,
              bottom: AppSpacing.verticalMedium,
            ),
            border: OutlineInputBorder(
              borderRadius: effectiveBorderRadius,
              borderSide: const BorderSide(color: AppColors.grey300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: effectiveBorderRadius,
              borderSide: const BorderSide(color: AppColors.grey300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: effectiveBorderRadius,
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: effectiveBorderRadius,
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: effectiveBorderRadius,
              borderSide: const BorderSide(color: AppColors.error, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: effectiveBorderRadius,
              borderSide: const BorderSide(color: AppColors.grey200),
            ),
          ),
        ),
      ],
    );
  }
}
