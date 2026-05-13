import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Dropdown selector field.
/// 
/// Features:
/// - Custom items builder
/// - Validation support
/// - RTL support
/// - Custom styling
/// 
/// Example:
/// ```dart
/// AppDropdownField<String>(
///   label: 'Category',
///   hintText: 'Select category',
///   items: ['Option 1', 'Option 2', 'Option 3'],
///   itemBuilder: (item) => Text(item),
///   validator: (value) => value == null ? 'Required' : null,
/// )
/// ```
class AppDropdownField<T> extends StatefulWidget {
  /// Field label displayed above the dropdown.
  final String? label;

  /// Placeholder text when no value is selected.
  final String? hintText;

  /// Current selected value.
  final T? value;

  /// Callback when value changes.
  final ValueChanged<T?>? onChanged;

  /// List of items to display.
  final List<T> items;

  /// Builder for dropdown items.
  final Widget Function(T) itemBuilder;

  /// Validation function.
  final FormFieldValidator<T?>? validator;

  /// Whether field is required.
  final bool isRequired;

  /// Whether field is enabled.
  final bool enabled;

  /// Icon displayed before the dropdown.
  final IconData? prefixIcon;

  /// Dropdown icon.
  final IconData? dropdownIcon;

  /// Field height.
  final double? height;

  const AppDropdownField({
    super.key,
    this.label,
    this.hintText,
    this.value,
    this.onChanged,
    required this.items,
    required this.itemBuilder,
    this.validator,
    this.isRequired = false,
    this.enabled = true,
    this.prefixIcon,
    this.dropdownIcon,
    this.height,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height ?? AppConstants.inputFieldHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Row(
            children: [
              Text(
                widget.label!,
                style: AppTextStyles.bodyMedium.copyWith(
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
        SizedBox(
          height: effectiveHeight,
          child: DropdownButtonFormField<T>(
            initialValue: widget.value,
            onChanged: widget.enabled ? widget.onChanged : null,
            validator: widget.validator,
            items: widget.items
                .map((item) => DropdownMenuItem<T>(
                      value: item,
                      child: widget.itemBuilder(item),
                    ))
                .toList(),
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textTertiary,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: AppColors.textTertiary,
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
              errorBorder: OutlineInputBorder(
                borderRadius: AppConstants.borderRadiusSmallRadius,
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: AppConstants.borderRadiusSmallRadius,
                borderSide: const BorderSide(color: AppColors.error, width: 2),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: AppConstants.borderRadiusSmallRadius,
                borderSide: const BorderSide(color: AppColors.grey200),
              ),
            ),
            icon: widget.dropdownIcon != null
                ? Icon(widget.dropdownIcon)
                : const Icon(Icons.arrow_drop_down),
            dropdownColor: AppColors.white,
            borderRadius: AppConstants.borderRadiusMediumRadius,
            isExpanded: true,
          ),
        ),
      ],
    );
  }
}
