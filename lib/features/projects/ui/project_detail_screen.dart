import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../delivery_receipts/ui/delivery_receipts_section.dart';
import '../logic/project_detail_cubit.dart';
import 'letterhead_picker.dart';

void openProjectDetail(BuildContext context, Project project, Entity entity) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => sl<ProjectDetailCubit>(param1: project)..load(),
        child: ProjectDetailScreen(entity: entity),
      ),
    ),
  );
}

class ProjectDetailScreen extends StatelessWidget {
  final Entity entity;
  const ProjectDetailScreen({super.key, required this.entity});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    final role = auth is AuthAuthenticated ? auth.profile.role : null;
    // Mirrors the projects UPDATE policy and the letterhead bucket's write policy.
    final canEditLetterhead = role == UserRole.verifier || role == UserRole.manager || role == UserRole.admin;

    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        final cubit = context.read<ProjectDetailCubit>();
        return Scaffold(
          appBar: AppBar(title: Text(state.project.name)),
          floatingActionButton: state.canEditItems
              ? FloatingActionButton.extended(
                  onPressed: () => _editItem(context, null),
                  icon: const Icon(Icons.add),
                  label: const Text('بند جديد'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Text(entity.name, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                _LetterheadCard(
                  url: state.project.letterheadImageUrl,
                  onChange: canEditLetterhead ? () => _changeLetterhead(context) : null,
                ),
                const SizedBox(height: 16),
                _ItemsCard(
                  state: state,
                  onEdit: (item) => _editItem(context, item),
                  onDelete: (item) => _deleteItem(context, item),
                ),
                DeliveryReceiptsSection.forProject(state.project.id),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeLetterhead(BuildContext context) async {
    final cubit = context.read<ProjectDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickLetterhead();
    if (picked == null) return;
    final error = await cubit.replaceLetterhead(picked);
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'تم تحديث نموذج السند')));
  }

  Future<void> _deleteItem(BuildContext context, ProjectItem item) async {
    final cubit = context.read<ProjectDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف البند'),
        content: Text('حذف "${item.itemName}" من عرض المشروع؟ السندات السابقة لن تتأثر.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final error = await cubit.deleteItem(item.id);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editItem(BuildContext context, ProjectItem? item) async {
    final cubit = context.read<ProjectDetailCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemForm(
        projectId: cubit.state.project.id,
        item: item,
        onSave: cubit.saveItem,
      ),
    );
  }
}

class _LetterheadCard extends StatelessWidget {
  final String? url;
  final VoidCallback? onChange;
  const _LetterheadCard({required this.url, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text('نموذج السند', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (onChange != null)
                TextButton.icon(
                  onPressed: onChange,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(url == null ? 'إضافة' : 'تغيير'),
                ),
            ]),
            if (url == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا يوجد نموذج سند -- السند سيُنشأ بدون رأس'),
              )
            else
              Image.network(url!, height: 90, fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final ProjectDetailState state;
  final ValueChanged<ProjectItem> onEdit;
  final ValueChanged<ProjectItem> onDelete;
  const _ItemsCard({required this.state, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showPrices = state.items.any((i) => i.unitPrice != null || i.totalPrice != null);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('بنود العرض', style: theme.textTheme.titleSmall),
            ),
            if (state.loading)
              const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
            else if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (state.items.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد بنود بعد'))
            else ...[
              for (final item in state.items)
                ListTile(
                  title: Text(item.itemName),
                  subtitle: Text([
                    if (item.description != null && item.description!.isNotEmpty) item.description!,
                    '${formatQty(item.quantity)} ${item.unit}',
                    if (item.unitPrice != null) 'سعر الوحدة: ${formatQty(item.unitPrice!)}',
                  ].join(' · ')),
                  trailing: item.totalPrice == null ? null : Text(formatQty(item.totalPrice!)),
                  onTap: state.canEditItems ? () => onEdit(item) : null,
                  onLongPress: state.canEditItems ? () => onDelete(item) : null,
                ),
              if (showPrices)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    Text('الإجمالي', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text(formatQty(state.quotationTotal), style: theme.textTheme.titleSmall),
                  ]),
                ),
              if (state.canEditItems)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text('اضغط للتعديل، اضغط مطولاً للحذف', style: theme.textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemForm extends StatefulWidget {
  final String projectId;
  final ProjectItem? item;
  final Future<String?> Function(ProjectItem) onSave;
  const _ItemForm({required this.projectId, required this.item, required this.onSave});

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late final _name = TextEditingController(text: widget.item?.itemName);
  late final _desc = TextEditingController(text: widget.item?.description);
  late final _qty = TextEditingController(text: widget.item == null ? '' : formatQty(widget.item!.quantity));
  late final _unit = TextEditingController(text: widget.item?.unit);
  late final _price = TextEditingController(
      text: widget.item?.unitPrice == null ? '' : formatQty(widget.item!.unitPrice!));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _desc, _qty, _unit, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _total {
    final q = double.tryParse(_qty.text.trim());
    final p = double.tryParse(_price.text.trim());
    return q == null || p == null ? null : q * p;
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qty.text.trim());
    if (_name.text.trim().isEmpty || _unit.text.trim().isEmpty || qty == null) {
      setState(() => _error = 'الاسم والكمية والوحدة مطلوبة');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(ProjectItem(
      id: widget.item?.id ?? '',
      projectId: widget.projectId,
      itemName: _name.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      quantity: qty,
      unit: _unit.text.trim(),
      unitPrice: double.tryParse(_price.text.trim()),
      totalPrice: _total,
    ));
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.item == null ? 'بند جديد' : 'تعديل البند', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'البند', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'الوصف (اختياري)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qty,
                keyboardType: numeric,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'الوحدة', border: OutlineInputBorder())),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _price,
            keyboardType: numeric,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'سعر الوحدة (اختياري)',
              border: const OutlineInputBorder(),
              helperText: _total == null ? null : 'الإجمالي: ${formatQty(_total!)}',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
