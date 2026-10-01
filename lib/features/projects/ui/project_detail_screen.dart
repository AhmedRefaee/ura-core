import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/project.dart';
import '../../../shared/logic/unit_conversion.dart';
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
import '../../../core/logic/debouncer.dart';
import '../../../core/storage/signed_storage_url.dart';

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
                    onRemove: canEditLetterhead
                        ? () => _removeLetterhead(context)
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

  Future<void> _removeLetterhead(BuildContext context) async {
    final cubit = context.read<ProjectDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إزالة نموذج السند؟'),
        content: const Text('سيُنشأ السند بدون رأس بعد ذلك، حتى تضاف صورة جديدة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await cubit.removeLetterhead();
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'تمت إزالة نموذج السند')),
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

/// The letterhead lives in a private bucket: fetch a signed URL once per
/// stored value, and decode at display size rather than full resolution.
class _LetterheadImage extends StatefulWidget {
  final String stored;
  const _LetterheadImage({required this.stored});

  @override
  State<_LetterheadImage> createState() => _LetterheadImageState();
}

class _LetterheadImageState extends State<_LetterheadImage> {
  late Future<String?> _url = SignedStorageUrl.resolve('project-letterheads', widget.stored);

  @override
  void didUpdateWidget(_LetterheadImage old) {
    super.didUpdateWidget(old);
    if (old.stored != widget.stored) {
      _url = SignedStorageUrl.resolve('project-letterheads', widget.stored);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: FutureBuilder<String?>(
        future: _url,
        builder: (context, snap) {
          final url = snap.data;
          if (url == null) {
            return snap.connectionState == ConnectionState.done
                ? const Center(child: Icon(Icons.broken_image_outlined))
                : const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          return Image.network(
            url,
            fit: BoxFit.contain,
            cacheHeight: (90 * MediaQuery.devicePixelRatioOf(context)).round(),
          );
        },
      ),
    );
  }
}

class _LetterheadCard extends StatelessWidget {
  final String? url;
  final VoidCallback? onChange;
  final VoidCallback? onRemove;
  const _LetterheadCard({required this.url, required this.onChange, required this.onRemove});

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
                if (url != null && onRemove != null)
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('إزالة'),
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  ),
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
              _LetterheadImage(stored: url!),
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

class _ProjectItemsTableScreen extends StatefulWidget {
  const _ProjectItemsTableScreen();

  @override
  State<_ProjectItemsTableScreen> createState() => _ProjectItemsTableScreenState();
}

class _ProjectItemsTableScreenState extends State<_ProjectItemsTableScreen> {
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer(const Duration(milliseconds: 200));
  String _query = '';

  // Search keys are folded once per items list, not per keystroke.
  List<ProjectItem>? _keyedItems;
  List<String> _keys = const [];

  @override
  void dispose() {
    _searchDebounce.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProjectItem> _filter(List<ProjectItem> items) {
    if (!identical(items, _keyedItems)) {
      _keyedItems = items;
      _keys = [for (final i in items) boqSearchKey(i)];
    }
    final words = foldForSearch(_query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return items;
    return [
      for (var i = 0; i < items.length; i++)
        if (words.every(_keys[i].contains)) items[i],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        final canEdit = state.canEditItems;
        final shown = _filter(state.items);
        final theme = Theme.of(context);
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم البند أو الوصف أو الفئة',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchDebounce.cancel();
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          if (v.length <= 1) setState(() {}); // clear button
                          _searchDebounce.run(() {
                            if (mounted) setState(() => _query = v);
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                      child: Text(
                        [
                          _query.trim().isEmpty
                              ? '${state.items.length} بند'
                              : '${shown.length} من ${state.items.length} بند',
                          if (canEdit) 'اضغط على الصف للتعديل، مطولاً للحذف',
                        ].join('  ·  '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(child: Text('لا توجد بنود مطابقة'))
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                              child: BoqTable(
                                items: shown,
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

  // Packaging: optional, for converting an actual delivery into this
  // item's registered unit on a سند (see unit_conversion.dart). Enabled
  // automatically when editing an item that already has it set.
  late bool _packagingEnabled = widget.item != null && registeredPackagingOf(widget.item!) != null;
  late final _packSize = TextEditingController(
    text: widget.item?.packagingUnitSize == null ? '' : formatQty(widget.item!.packagingUnitSize!),
  );
  late final _packCount = TextEditingController(
    text: widget.item?.packagingUnitCount == null ? '' : formatQty(widget.item!.packagingUnitCount!),
  );
  late QuantityUnit? _baseUnit = QuantityUnit.tryParse(widget.item?.packagingBaseUnit);

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_category, _name, _desc, _qty, _unit, _price, _packSize, _packCount]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _total {
    final q = parseLocalizedNumber(_qty.text);
    final p = parseLocalizedNumber(_price.text);
    return q == null || p == null ? null : round2(q * p);
  }

  /// `"1 <unit> = <total> <base unit label>"`, confirming what was just
  /// typed before the item is saved.
  String? get _packagingPreview {
    final size = parseLocalizedNumber(_packSize.text);
    final count = parseLocalizedNumber(_packCount.text);
    if (size == null || count == null || _baseUnit == null) return null;
    final unitLabel = _unit.text.trim().isEmpty ? 'وحدة' : _unit.text.trim();
    return '1 $unitLabel = ${formatQty(size * count)} ${_baseUnit!.label}';
  }

  Future<void> _save() async {
    final qty = parseLocalizedNumber(_qty.text);
    final price = parseLocalizedNumber(_price.text);
    if (_name.text.trim().isEmpty || _unit.text.trim().isEmpty || qty == null) {
      setState(() => _error = 'الاسم والكمية والوحدة مطلوبة، والكمية رقم');
      return;
    }
    if (_price.text.trim().isNotEmpty && price == null) {
      // Saving would silently drop the price.
      setState(() => _error = 'سعر الوحدة ليس رقماً');
      return;
    }
    final packSize = parseLocalizedNumber(_packSize.text);
    final packCount = parseLocalizedNumber(_packCount.text);
    if (_packagingEnabled && (packSize == null || packSize <= 0 || packCount == null || packCount <= 0 || _baseUnit == null)) {
      setState(() => _error = 'أكمل حجم العبوة والوحدة والعدد، أو عطّل تفاصيل التعبئة');
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
        unitPrice: price,
        totalPrice: _total,
        packagingUnitSize: _packagingEnabled ? packSize : null,
        packagingUnitCount: _packagingEnabled ? packCount : null,
        packagingBaseUnit: _packagingEnabled ? _baseUnit!.name : null,
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
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تفاصيل التعبئة'),
            subtitle: const Text('لحساب كمية السند تلقائياً من الكمية الفعلية المسلّمة'),
            value: _packagingEnabled,
            onChanged: (v) => setState(() => _packagingEnabled = v),
          ),
          if (_packagingEnabled) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _packSize,
                    keyboardType: numeric,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'حجم العبوة الواحدة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<QuantityUnit>(
                    initialValue: _baseUnit,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final u in QuantityUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: (u) => setState(() => _baseUnit = u),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _packCount,
              keyboardType: numeric,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'عدد العبوات لكل "${_unit.text.trim().isEmpty ? 'وحدة' : _unit.text.trim()}"',
                border: const OutlineInputBorder(),
                helperText: _packagingPreview,
              ),
            ),
          ],
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
