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
import '../logic/boq_excel.dart';
import '../logic/boq_excel_cubit.dart';
import '../logic/project_detail_cubit.dart';
import 'boq_import_preview_screen.dart';
import 'boq_table.dart';
import 'letterhead_picker.dart';

void openProjectDetail(BuildContext context, Project project, Entity entity) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => sl<ProjectDetailCubit>(param1: project)..load(),
          ),
          BlocProvider(create: (_) => sl<BoqExcelCubit>()),
        ],
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
    final canEditLetterhead =
        role == UserRole.verifier ||
        role == UserRole.manager ||
        role == UserRole.admin;

    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        final cubit = context.read<ProjectDetailCubit>();
        return BlocListener<BoqExcelCubit, BoqExcelState>(
          listenWhen: (prev, curr) =>
              (curr is BoqExcelParsed &&
                  curr is! BoqExcelSaving &&
                  prev is! BoqExcelParsed) ||
              curr is BoqExcelImported ||
              curr is BoqExcelError,
          listener: (context, excelState) => _onExcelState(context, excelState),
          child: Scaffold(
            appBar: AppBar(
              title: Text(state.project.name),
              actions: [
                if (state.canEditItems) ...[
                  IconButton(
                    tooltip: 'تصدير Excel',
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: state.loading
                        ? null
                        : () => context.read<BoqExcelCubit>().export(
                            project: state.project,
                            entityName: entity.name,
                            items: state.items,
                          ),
                  ),
                  IconButton(
                    tooltip: 'استيراد Excel',
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: state.loading
                        ? null
                        : () => context.read<BoqExcelCubit>().pickAndParse(
                            state.project.id,
                          ),
                  ),
                ],
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: BlocBuilder<BoqExcelCubit, BoqExcelState>(
                  builder: (_, s) => s is BoqExcelBusy
                      ? const LinearProgressIndicator(minHeight: 2)
                      : const SizedBox(height: 2),
                ),
              ),
            ),
            floatingActionButton: state.canEditItems
                ? FloatingActionButton.extended(
                    onPressed: () => showProjectItemForm(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('بند جديد'),
                  )
                : null,
            body: RefreshIndicator(
              onRefresh: cubit.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Text(
                    entity.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _LetterheadCard(
                    url: state.project.letterheadImageUrl,
                    onChange: canEditLetterhead
                        ? () => _changeLetterhead(context)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _ItemsCard(state: state),
                  DeliveryReceiptsSection.forProject(state.project.id),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onExcelState(BuildContext context, BoqExcelState excelState) {
    final messenger = ScaffoldMessenger.of(context);
    final excel = context.read<BoqExcelCubit>();
    switch (excelState) {
      case BoqExcelParsed():
        final detail = context.read<ProjectDetailCubit>();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: excel,
              child: BoqImportPreviewScreen(
                projectId: detail.state.project.id,
                currentItemCount: detail.state.items.length,
              ),
            ),
          ),
        );
      case BoqExcelImported(:final count):
        messenger.showSnackBar(
          SnackBar(content: Text('تم استيراد $count بند')),
        );
        context.read<ProjectDetailCubit>().load();
      case BoqExcelError(:final message):
        messenger.showSnackBar(SnackBar(content: Text(message)));
        excel.reset();
      default:
        break;
    }
  }

  Future<void> _changeLetterhead(BuildContext context) async {
    final cubit = context.read<ProjectDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickLetterhead();
    if (picked == null) return;
    final error = await cubit.replaceLetterhead(picked);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'تم تحديث نموذج السند')),
    );
  }

}

Future<void> confirmDeleteProjectItem(BuildContext context, ProjectItem item) async {
  final cubit = context.read<ProjectDetailCubit>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حذف البند'),
      content: Text(
        'حذف "${item.itemName}" من عرض المشروع؟ السندات السابقة لن تتأثر.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final error = await cubit.deleteItem(item.id);
  if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
}

Future<void> showProjectItemForm(BuildContext context, ProjectItem? item) async {
  final cubit = context.read<ProjectDetailCubit>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ItemForm(
      projectId: cubit.state.project.id,
      item: item,
      categories: [
        for (final c in groupByCategory(cubit.state.items))
          if (c.name.isNotEmpty) c.name,
      ],
      nextSortOrder:
          cubit.state.items.fold<int>(
            0,
            (m, i) => i.sortOrder > m ? i.sortOrder : m,
          ) +
          1,
      onSave: cubit.saveItem,
    ),
  );
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
            Row(
              children: [
                Text(
                  'نموذج السند',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (onChange != null)
                  TextButton.icon(
                    onPressed: onChange,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(url == null ? 'إضافة' : 'تغيير'),
                  ),
              ],
            ),
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
  const _ItemsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPrices = state.items.any((i) => i.totalPrice != null);
    final totals = BoqTotals.of(state.items);
    final categories = groupByCategory(state.items).length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('بنود العرض', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (state.loading)
              const LinearProgressIndicator()
            else if (state.error != null)
              Text(state.error!, style: TextStyle(color: theme.colorScheme.error))
            else if (state.items.isEmpty)
              Text(state.canEditItems
                  ? 'لا توجد بنود بعد. أضف بنداً أو استورد ملف Excel من الأعلى.'
                  : 'لا توجد بنود بعد')
            else ...[
              Text('${state.items.length} بند في $categories ${categories == 1 ? 'فئة' : 'فئات'}'),
              if (hasPrices) ...[
                const SizedBox(height: 4),
                Text('الإجمالي: ${formatMoney(totals.subtotal)}  ·  شامل الضريبة: ${formatMoney(totals.total)}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: state.loading || (state.items.isEmpty && !state.canEditItems)
                  ? null
                  : () => openProjectItemsTable(context),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('عرض الجدول'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full quotation table on its own screen, so it gets the whole height
/// and stays lazy. Shares the project's cubit, so edits show up everywhere.
void openProjectItemsTable(BuildContext context) {
  final cubit = context.read<ProjectDetailCubit>();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BlocProvider.value(value: cubit, child: const _ProjectItemsTableScreen()),
  ));
}

class _ProjectItemsTableScreen extends StatelessWidget {
  const _ProjectItemsTableScreen();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        final canEdit = state.canEditItems;
        return Scaffold(
          appBar: AppBar(title: Text('بنود العرض — ${state.project.name}')),
          floatingActionButton: canEdit
              ? FloatingActionButton.extended(
                  onPressed: () => showProjectItemForm(context, null),
                  icon: const Icon(Icons.add),
                  label: const Text('بند جديد'),
                )
              : null,
          body: state.items.isEmpty
              ? const Center(child: Text('لا توجد بنود بعد'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canEdit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('اضغط على الصف للتعديل، اضغط مطولاً للحذف',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                        child: BoqTable(
                          items: state.items,
                          showPrices: canEdit || state.items.any((i) => i.totalPrice != null),
                          onTap: canEdit ? (item) => showProjectItemForm(context, item) : null,
                          onLongPress: canEdit ? (item) => confirmDeleteProjectItem(context, item) : null,
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _ItemForm extends StatefulWidget {
  final String projectId;
  final ProjectItem? item;
  final List<String> categories;
  final int nextSortOrder;
  final Future<String?> Function(ProjectItem) onSave;
  const _ItemForm({
    required this.projectId,
    required this.item,
    required this.categories,
    required this.nextSortOrder,
    required this.onSave,
  });

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late final _category = TextEditingController(
    text:
        widget.item?.category ??
        (widget.categories.length == 1 ? widget.categories.single : ''),
  );
  late final _name = TextEditingController(text: widget.item?.itemName);
  late final _desc = TextEditingController(text: widget.item?.description);
  late final _qty = TextEditingController(
    text: widget.item == null ? '' : formatQty(widget.item!.quantity),
  );
  late final _unit = TextEditingController(text: widget.item?.unit);
  late final _price = TextEditingController(
    text: widget.item?.unitPrice == null
        ? ''
        : formatQty(widget.item!.unitPrice!),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_category, _name, _desc, _qty, _unit, _price]) {
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
    final error = await widget.onSave(
      ProjectItem(
        id: widget.item?.id ?? '',
        projectId: widget.projectId,
        category: _category.text.trim(),
        sortOrder: widget.item?.sortOrder ?? widget.nextSortOrder,
        itemName: _name.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        quantity: qty,
        unit: _unit.text.trim(),
        unitPrice: double.tryParse(_price.text.trim()),
        totalPrice: _total,
      ),
    );
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
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.item == null ? 'بند جديد' : 'تعديل البند',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'الفئة (مثال: المخبوزات)',
              helperText: 'اتركها فارغة إن لم يكن العرض مقسماً إلى جداول',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in widget.categories)
                    ActionChip(
                      label: Text(c),
                      onPressed: () => setState(() => _category.text = c),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'البند',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
              labelText: 'الوصف (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: numeric,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _unit,
                  decoration: const InputDecoration(
                    labelText: 'الوحدة',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _price,
            keyboardType: numeric,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'سعر الوحدة (اختياري)',
              border: const OutlineInputBorder(),
              helperText: _total == null
                  ? null
                  : 'الإجمالي: ${formatQty(_total!)}',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
