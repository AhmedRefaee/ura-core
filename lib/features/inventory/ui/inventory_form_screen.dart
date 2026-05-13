import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../logic/inventory_form_cubit.dart';

class CustomItemPrefill {
  final String name;
  final int quantity;
  final String unit;
  final String? sku;
  final String? category;
  final int minQuantity;
  final String? description;

  const CustomItemPrefill({
    required this.name,
    required this.quantity,
    required this.unit,
    this.sku,
    this.category,
    this.minQuantity = 0,
    this.description,
  });
}

class InventoryFormScreen extends StatelessWidget {
  final InventoryItem? initialItem;
  final CustomItemPrefill? prefill;

  const InventoryFormScreen({super.key, this.initialItem, this.prefill});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl.get<InventoryFormCubit>(param1: initialItem),
      child: _InventoryFormView(initialItem: initialItem, prefill: prefill),
    );
  }
}

class _InventoryFormView extends StatefulWidget {
  final InventoryItem? initialItem;
  final CustomItemPrefill? prefill;
  const _InventoryFormView({this.initialItem, this.prefill});

  @override
  State<_InventoryFormView> createState() => _InventoryFormViewState();
}

class _InventoryFormViewState extends State<_InventoryFormView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _minQuantityCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    final pre = widget.prefill;
    _nameCtrl = TextEditingController(text: item?.itemName ?? pre?.name ?? '');
    _skuCtrl = TextEditingController(text: item?.sku ?? pre?.sku ?? '');
    _unitCtrl = TextEditingController(text: item?.unit ?? pre?.unit ?? 'قطعة');
    _quantityCtrl = TextEditingController(
        text: item != null ? '${item.quantity}' : pre != null ? '${pre.quantity}' : '');
    _categoryCtrl = TextEditingController(text: item?.category ?? pre?.category ?? '');
    _minQuantityCtrl = TextEditingController(
        text: '${item?.minQuantity ?? pre?.minQuantity ?? 0}');
    _descriptionCtrl = TextEditingController(text: item?.description ?? pre?.description ?? '');
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _unitCtrl.dispose();
    _quantityCtrl.dispose();
    _categoryCtrl.dispose();
    _minQuantityCtrl.dispose();
    _descriptionCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialItem != null;

    return BlocConsumer<InventoryFormCubit, InventoryFormState>(
      listener: (context, state) {
        if (state is InventoryFormSuccess) {
          Navigator.pop(context, true);
        }
        if (state is InventoryFormError) {
          AppSnackbar.show(
            context,
            message: state.message,
            variant: AppSnackbarVariant.error,
          );
        }
      },
      builder: (context, state) {
        final isSaving = state is InventoryFormSaving;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'تعديل الصنف' : 'إضافة صنف جديد'),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: AppSpacing.allMedium,
              children: [
                _SectionLabel('معلومات أساسية'),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _nameCtrl,
                  label: 'اسم الصنف',
                  required: true,
                  enabled: !isSaving,
                ),
                SizedBox(height: AppSpacing.verticalSmall),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _Field(
                        controller: _quantityCtrl,
                        label: 'الكمية',
                        required: true,
                        keyboardType: TextInputType.number,
                        enabled: !isSaving,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'مطلوب';
                          if (int.tryParse(v) == null || int.parse(v) < 0) {
                            return 'رقم غير صالح';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: AppSpacing.horizontalSmall),
                    Expanded(
                      child: _Field(
                        controller: _unitCtrl,
                        label: 'الوحدة',
                        required: true,
                        enabled: !isSaving,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _skuCtrl,
                  label: 'رمز SKU',
                  required: false,
                  enabled: !isSaving,
                ),
                SizedBox(height: AppSpacing.verticalLarge),
                _SectionLabel('تصنيف وتنبيهات'),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _categoryCtrl,
                  label: 'الفئة',
                  required: false,
                  enabled: !isSaving,
                ),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _minQuantityCtrl,
                  label: 'حد التنبيه (كمية منخفضة)',
                  required: false,
                  keyboardType: TextInputType.number,
                  enabled: !isSaving,
                  validator: (v) {
                    if (v != null && v.isNotEmpty) {
                      if (int.tryParse(v) == null || int.parse(v) < 0) {
                        return 'رقم غير صالح';
                      }
                    }
                    return null;
                  },
                ),
                SizedBox(height: AppSpacing.verticalLarge),
                _SectionLabel('معلومات إضافية'),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _descriptionCtrl,
                  label: 'الوصف',
                  required: false,
                  maxLines: 3,
                  enabled: !isSaving,
                ),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _notesCtrl,
                  label: 'ملاحظات (تُحفظ في سجل التغييرات)',
                  required: false,
                  maxLines: 2,
                  enabled: !isSaving,
                ),
                SizedBox(height: AppSpacing.verticalXXLarge),
                AppButton(
                  onPressed: isSaving ? null : _submit,
                  text: isEditing ? 'حفظ التعديلات' : 'إضافة الصنف',
                  isLoading: isSaving,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<InventoryFormCubit>().submit(
          name: _nameCtrl.text.trim(),
          unit: _unitCtrl.text.trim(),
          quantity: int.parse(_quantityCtrl.text.trim()),
          sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? null
              : _categoryCtrl.text.trim(),
          minQuantity: int.tryParse(_minQuantityCtrl.text.trim()) ?? 0,
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        color: AppColors.primary,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool enabled;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.required,
    required this.enabled,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        ),
      ),
      validator: validator ??
          (required
              ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
              : null),
    );
  }
}
