import 'package:flutter/material.dart';
import '../../../../shared/models/entity.dart';
import '../../logic/entities_cubit.dart';

Future<void> showEntityFormSheet(
  BuildContext context,
  EntitiesCubit cubit, {
  Entity? entity,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => EntityFormSheet(cubit: cubit, entity: entity),
  );
}

class EntityFormSheet extends StatefulWidget {
  final EntitiesCubit cubit;
  final Entity? entity;

  const EntityFormSheet({super.key, required this.cubit, this.entity});

  @override
  State<EntityFormSheet> createState() => _EntityFormSheetState();
}

class _EntityFormSheetState extends State<EntityFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _contactPhoneCtrl;
  late final TextEditingController _addressCtrl;
  late EntityCategory _category;
  bool _loading = false;

  bool get _isEdit => widget.entity != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entity;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _contactNameCtrl = TextEditingController(text: e?.contactName ?? '');
    _contactPhoneCtrl = TextEditingController(text: e?.contactPhone ?? '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _category = e?.category ?? EntityCategory.unassigned;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isEdit) {
        await widget.cubit.edit(
          id: widget.entity!.id,
          name: _nameCtrl.text,
          category: _category,
          contactName: _contactNameCtrl.text,
          contactPhone: _contactPhoneCtrl.text,
          address: _addressCtrl.text,
        );
      } else {
        await widget.cubit.add(
          name: _nameCtrl.text,
          category: _category,
          contactName: _contactNameCtrl.text,
          contactPhone: _contactPhoneCtrl.text,
          address: _addressCtrl.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEdit ? 'تعديل الجهة' : 'إضافة جهة',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 16),

              // Category chips
              Text('التصنيف *', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: EntityCategory.values.map((cat) {
                  return ChoiceChip(
                    label: Text(cat.label),
                    selected: _category == cat,
                    onSelected: (_) => setState(() => _category = cat),
                    avatar: Icon(
                      _categoryIcon(cat),
                      size: 16,
                      color: _category == cat
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Contact name
              TextFormField(
                controller: _contactNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم جهة الاتصال (اختياري)',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Contact phone
              TextFormField(
                controller: _contactPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (اختياري)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Address
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياري)',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              // Save button
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'حفظ التعديلات' : 'إضافة الجهة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(EntityCategory cat) {
    switch (cat) {
      case EntityCategory.incoming:
        return Icons.arrow_downward;
      case EntityCategory.outgoing:
        return Icons.arrow_upward;
      case EntityCategory.unassigned:
        return Icons.swap_horiz;
    }
  }
}
