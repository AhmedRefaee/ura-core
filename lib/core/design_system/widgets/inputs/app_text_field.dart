import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme.dart';

/// Text input field with validation support.
/// 
/// Features:
/// - Built-in validation
/// - Custom prefix/suffix icons
/// - Character counter
/// - RTL support
/// - Accessibility support
/// 
/// Example:
/// ```dart
/// AppTextField(
///   label: 'Email',
///   hintText: 'Enter your email',
///   keyboardType: TextInputType.emailAddress,
///   validator: (value) => value!.isEmpty ? 'Required' : null,
/// )
/// ```
class AppTextField extends StatefulWidget {
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

  /// Text input type.
  final TextInputType? keyboardType;

  /// Text capitalization mode.
  final TextCapitalization textCapitalization;

  /// Maximum number of lines.
  final int? maxLines;

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

  /// Icon displayed before the text.
  final IconData? prefixIcon;

  /// Widget displayed before the text.
  final Widget? prefix;

  /// Icon displayed after the text.
  final IconData? suffixIcon;

  /// Callback when suffix icon is pressed.
  final VoidCallback? onSuffixIconPressed;

  /// Widget displayed after the text.
  final Widget? suffix;

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

  /// Field height.
  final double? height;

  const AppTextField({
    super.key,
    this.label,
    this.hintText,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.isRequired = false,
    this.readOnly = false,
    this.enabled = true,
    this.prefixIcon,
    this.prefix,
    this.suffixIcon,
    this.onSuffixIconPressed,
    this.suffix,
    this.inputFormatters,
    this.controller,
    this.focusNode,
    this.textStyle,
    this.labelStyle,
    this.hintStyle,
    this.borderRadius,
    this.height,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _obscureText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode = widget.focusNode ?? FocusNode();
    _obscureText = widget.keyboardType == TextInputType.visiblePassword;
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
      _isFocused = _focusNode.hasFocus;
    });
  }

  void _toggleObscureText() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveHeight = widget.height ?? AppConstants.inputFieldHeight;
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
                  color: theme.textTheme.bodyMedium?.color,
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
        SizedBox(
          height: widget.maxLines != null && widget.maxLines! > 1 ? null : effectiveHeight,
          child: TextFormField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: widget.onChanged,
            validator: widget.validator,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            readOnly: widget.readOnly,
            enabled: widget.enabled,
            obscureText: _obscureText,
            inputFormatters: widget.inputFormatters,
            style: widget.textStyle ?? AppTextStyles.bodyLarge.copyWith(
              color: theme.textTheme.bodyLarge?.color,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: widget.hintStyle ?? AppTextStyles.bodyLarge.copyWith(
                color: theme.hintColor,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: _isFocused ? AppColors.primary : theme.hintColor,
                    )
                  : widget.prefix,
              suffixIcon: _buildSuffixIcon(),
              suffix: widget.suffix,
              counterText: widget.showCounter ? null : '',
              filled: true,
              fillColor: widget.enabled
                  ? theme.inputDecorationTheme.fillColor ?? theme.scaffoldBackgroundColor
                  : theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
              contentPadding: AppSpacing.horizontalLargePadding.copyWith(
                top: AppSpacing.verticalMedium,
                bottom: AppSpacing.verticalMedium,
              ),
              border: OutlineInputBorder(
                borderRadius: effectiveBorderRadius,
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: effectiveBorderRadius,
                borderSide: BorderSide(color: theme.dividerColor),
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
                borderSide: BorderSide(color: theme.disabledColor),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildSuffixIcon() {
    final theme = Theme.of(context);
    if (widget.keyboardType == TextInputType.visiblePassword) {
      return IconButton(
        icon: Icon(
          _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: theme.hintColor,
        ),
        onPressed: _toggleObscureText,
      );
    }

    if (widget.suffixIcon != null) {
      return IconButton(
        icon: Icon(widget.suffixIcon),
        color: _isFocused ? AppColors.primary : theme.hintColor,
        onPressed: widget.onSuffixIconPressed,
      );
    }

    return widget.suffix;
  }
}
