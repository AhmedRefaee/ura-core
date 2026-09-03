import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/profile.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../../shared/utils/quantity_format.dart';
import '../logic/inventory_form_cubit.dart';

class CustomItemPrefill {
  final String name;
  final double quantity;
  final String unit;
  final String? sku;
  final String? category;
  final double minQuantity;
  final String? description;
  final String? brand;
  final String? variety;
  final double? packagingSize;
  final String? packagingSizeUnit;
  final List<String>? aliases;

  const CustomItemPrefill({
    required this.name,
    required this.quantity,
    required this.unit,
    this.sku,
    this.category,
    this.minQuantity = 3,
    this.description,
    this.brand,
    this.variety,
    this.packagingSize,
    this.packagingSizeUnit,
    this.aliases,
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
  late final TextEditingController _brandCtrl;
  late final TextEditingController _varietyCtrl;
  late final TextEditingController _packagingSizeCtrl;
  late final TextEditingController _packagingSizeUnitCtrl;
  late final TextEditingController _aliasesCtrl;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    final pre = widget.prefill;
    _nameCtrl = TextEditingController(text: item?.itemName ?? pre?.name ?? '');
    _skuCtrl = TextEditingController(text: item?.sku ?? pre?.sku ?? '');
    _unitCtrl = TextEditingController(text: item?.unit ?? pre?.unit ?? 'قطعة');
    // A verifier gets '0' rather than '' when there is nothing to prefill from:
    // their quantity field is disabled, so an empty one would fail the required
    // validator with no way for them to fix it. Storage still starts blank, so
    // entering a real count stays a conscious act.
    final isVerifier = context.read<AuthCubit>().state is AuthAuthenticated &&
        (context.read<AuthCubit>().state as AuthAuthenticated).profile.role ==
            UserRole.verifier;
    _quantityCtrl = TextEditingController(
        text: item != null
            ? formatQty(item.quantity)
            : pre != null
                ? formatQty(pre.quantity)
                : (isVerifier ? '0' : ''));
    _categoryCtrl = TextEditingController(text: item?.category ?? pre?.category ?? '');
    _minQuantityCtrl = TextEditingController(
        text: formatQty(item?.minQuantity ?? pre?.minQuantity ?? 3));
    _descriptionCtrl = TextEditingController(text: item?.description ?? pre?.description ?? '');
    _notesCtrl = TextEditingController();
    _brandCtrl = TextEditingController(text: item?.brand ?? pre?.brand ?? '');
    _varietyCtrl = TextEditingController(text: item?.variety ?? pre?.variety ?? '');
    final packagingSize = item?.packagingSize ?? pre?.packagingSize;
    _packagingSizeCtrl = TextEditingController(
        text: packagingSize == null ? '' : formatQty(packagingSize));
    _packagingSizeUnitCtrl = TextEditingController(
        text: item?.packagingSizeUnit ?? pre?.packagingSizeUnit ?? '');
    _aliasesCtrl = TextEditingController(
        text: (item?.aliases ?? pre?.aliases)?.join(', ') ?? '');
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
    _brandCtrl.dispose();
    _varietyCtrl.dispose();
    _packagingSizeCtrl.dispose();
    _packagingSizeUnitCtrl.dispose();
    _aliasesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialItem != null;

    // The stock count belongs to whoever is standing in the warehouse. A
    // verifier reaches this screen to add a product or fix its details, and
    // inventory_create_item/inventory_update_item discard any quantity they
    // send -- so showing them a live field would be a lie about what saving
    // does. This only makes that server rule visible; it does not enforce it.
    final authState = context.watch<AuthCubit>().state;
    final isVerifier = authState is AuthAuthenticated &&
        authState.profile.role == UserRole.verifier;

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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [quantityInputFormatter],
                        enabled: !isSaving && !isVerifier,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'مطلوب';
                          final n = double.tryParse(v);
                          if (n == null || n < 0) {
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
                if (isVerifier)
                  Padding(
                    padding: EdgeInsets.only(top: AppSpacing.verticalXSmall),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: AppSpacing.horizontalSmall),
                        Expanded(
                          child: Text(
                            'الكمية يحددها أمين المخزن فقط',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _brandCtrl,
                        label: 'العلامة التجارية',
                        required: false,
                        enabled: !isSaving,
                      ),
                    ),
                    SizedBox(width: AppSpacing.horizontalSmall),
                    Expanded(
                      child: _Field(
                        controller: _varietyCtrl,
                        label: 'النوع',
                        required: false,
                        enabled: !isSaving,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.verticalSmall),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _Field(
                        controller: _packagingSizeCtrl,
                        label: 'حجم التعبئة',
                        required: false,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [quantityInputFormatter],
                        enabled: !isSaving,
                        validator: (v) {
                          if (v != null && v.isNotEmpty) {
                            final n = double.tryParse(v);
                            if (n == null || n < 0) {
                              return 'رقم غير صالح';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: AppSpacing.horizontalSmall),
                    Expanded(
                      child: _Field(
                        controller: _packagingSizeUnitCtrl,
                        label: 'وحدة التعبئة',
                        required: false,
                        enabled: !isSaving,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.verticalSmall),
                _Field(
                  controller: _minQuantityCtrl,
                  label: 'حد التنبيه (كمية منخفضة)',
                  required: false,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [quantityInputFormatter],
                  enabled: !isSaving,
                  validator: (v) {
                    if (v != null && v.isNotEmpty) {
                      final n = double.tryParse(v);
                      if (n == null || n < 0) {
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
                  controller: _aliasesCtrl,
                  label: 'أسماء بديلة (افصل بفاصلة)',
                  required: false,
                  maxLines: 2,
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
    final aliases = _aliasesCtrl.text
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    context.read<InventoryFormCubit>().submit(
          name: _nameCtrl.text.trim(),
          unit: _unitCtrl.text.trim(),
          quantity: double.parse(_quantityCtrl.text.trim()),
          sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? null
              : _categoryCtrl.text.trim(),
          minQuantity: double.tryParse(_minQuantityCtrl.text.trim()) ?? 3,
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
          variety: _varietyCtrl.text.trim().isEmpty ? null : _varietyCtrl.text.trim(),
          packagingSize: double.tryParse(_packagingSizeCtrl.text.trim()),
          packagingSizeUnit: _packagingSizeUnitCtrl.text.trim().isEmpty
              ? null
              : _packagingSizeUnitCtrl.text.trim(),
          aliases: aliases.isEmpty ? null : aliases,
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
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.required,
    required this.enabled,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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
