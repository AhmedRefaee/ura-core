import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../projects/logic/boq_excel.dart';
import '../logic/create_delivery_receipt_cubit.dart';

/// Opens the سند flow. Resolves to true once a سند was actually filed.
Future<bool> openCreateDeliveryReceipt(
  BuildContext context, {
  DeliveryReceiptLaunch launch = const DeliveryReceiptLaunch(),
}) async {
  final filed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => sl<CreateDeliveryReceiptCubit>(param1: launch)..init(),
        child: const CreateDeliveryReceiptScreen(),
      ),
    ),
  );
  return filed ?? false;
}

enum _Step { entity, project, items }

/// Three full-screen steps -- الجهة، المشروع، البنود -- built for a rep on
/// the move: one hand, big targets, no dropdowns to aim at. Back walks the
/// steps instead of leaving the flow.
class CreateDeliveryReceiptScreen extends StatelessWidget {
  const CreateDeliveryReceiptScreen({super.key});

  static _Step _stepOf(CreateDeliveryReceiptState s) => s.entity == null
      ? _Step.entity
      : (s.project == null ? _Step.project : _Step.items);

  static void _back(BuildContext context, CreateDeliveryReceiptState s) {
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    switch (_stepOf(s)) {
      case _Step.entity:
        Navigator.of(context).pop(false);
      case _Step.project:
        cubit.clearEntity();
      case _Step.items:
        // A single project was picked automatically; there's no project
        // step to go back to.
        s.projects.length <= 1 ? cubit.clearEntity() : cubit.clearProject();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateDeliveryReceiptCubit, CreateDeliveryReceiptState>(
      builder: (context, state) {
        if (state.receiptId != null && state.pdfBytes != null) {
          return _FiledView(state: state);
        }
        final step = _stepOf(state);
        return PopScope(
          canPop: step == _Step.entity,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !state.submitting) _back(context, state);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                '${context.read<CreateDeliveryReceiptCubit>().launch.isEdit ? 'تعديل السند' : 'سند جديد'} — ${switch (step) {
                  _Step.entity => 'الجهة',
                  _Step.project => 'المشروع',
                  _Step.items => 'البنود',
                }}',
              ),
              leading: BackButton(
                onPressed: state.submitting
                    ? null
                    : () => _back(context, state),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: state.loading
                      ? null
                      : (step.index + 1) / _Step.values.length,
                  minHeight: 4,
                ),
              ),
            ),
            body: switch (step) {
              _Step.entity => _EntityStep(state: state),
              _Step.project => _ProjectStep(state: state),
              _Step.items => _ItemsStep(state: state),
            },
          ),
        );
      },
    );
  }
}

// ── Shared bits ───────────────────────────────────────────────────────────────

/// What's been chosen so far, each tappable to change it.
class _Breadcrumb extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  const _Breadcrumb({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    final theme = Theme.of(context);
    Widget chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: state.submitting ? null : onTap,
    );
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (state.entity != null)
            chip(
              Icons.business_outlined,
              state.entity!.name,
              cubit.clearEntity,
            ),
          if (state.project != null)
            chip(
              Icons.work_outline,
              state.project!.name,
              state.projects.length <= 1
                  ? cubit.clearEntity
                  : cubit.clearProject,
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _EmptyHint({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 1: الجهة ─────────────────────────────────────────────────────────────

class _EntityStep extends StatefulWidget {
  final CreateDeliveryReceiptState state;
  const _EntityStep({required this.state});

  @override
  State<_EntityStep> createState() => _EntityStepState();
}

class _EntityStepState extends State<_EntityStep> {
  final _search = TextEditingController();
  // Reps deliver: توريد entities first; the chips switch it.
  EntityCategory? _category = EntityCategory.outgoing;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Entity> _visible(List<Entity> all, EntityCategory? category) {
    final words = foldForSearch(
      _query,
    ).split(' ').where((w) => w.isNotEmpty).toList();
    return [
      for (final e in all)
        if ((category == null || e.category == category) &&
            (words.isEmpty || words.every(foldForSearch(e.name).contains)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    if (state.loading && state.entities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final all = state.pickableEntities;
    if (all.isEmpty) {
      return _EmptyHint(
        icon: Icons.work_off_outlined,
        title: state.error ?? 'لا توجد جهات لديها مشاريع بعد',
        subtitle: state.error == null
            ? 'يضيف المشرف أو المدير المشاريع من شاشة إدارة الجهات'
            : null,
      );
    }
    final visible = _visible(all, _category);
    final otherMatches = _category == null ? 0 : _visible(all, null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) _ErrorBanner(state.error!),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _SearchField(
            controller: _search,
            hint: 'ابحث باسم الجهة',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (label, category) in [
                (EntityCategory.outgoing.label, EntityCategory.outgoing),
                (EntityCategory.incoming.label, EntityCategory.incoming),
                ('الكل', null),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: visible.isEmpty
              ? _EmptyHint(
                  icon: Icons.search_off,
                  title: 'لا توجد جهات مطابقة',
                  action: otherMatches > 0
                      ? OutlinedButton(
                          onPressed: () => setState(() => _category = null),
                          child: Text('عرض الكل ($otherMatches)'),
                        )
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final e = visible[i];
                    return _BigTile(
                      icon: e.category == EntityCategory.incoming
                          ? Icons.shopping_cart_outlined
                          : Icons.local_shipping_outlined,
                      title: e.name,
                      subtitle: [
                        e.category.label,
                        if (e.address != null && e.address!.isNotEmpty)
                          e.address!,
                      ].join(' · '),
                      onTap: () => cubit.selectEntity(e),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BigTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _BigTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 2: المشروع ───────────────────────────────────────────────────────────

class _ProjectStep extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  const _ProjectStep({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breadcrumb(state: state),
        if (state.error != null) _ErrorBanner(state.error!),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.projects.isEmpty
              ? _EmptyHint(
                  icon: Icons.work_off_outlined,
                  title: 'لا توجد مشاريع لهذه الجهة',
                  action: OutlinedButton(
                    onPressed: cubit.clearEntity,
                    child: const Text('اختر جهة أخرى'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: state.projects.length,
                  itemBuilder: (context, i) {
                    final p = state.projects[i];
                    return _BigTile(
                      icon: Icons.work_outline,
                      title: p.name,
                      onTap: () => cubit.selectProject(p),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Step 3: البنود ────────────────────────────────────────────────────────────

class _ItemsStep extends StatefulWidget {
  final CreateDeliveryReceiptState state;
  const _ItemsStep({required this.state});

  @override
  State<_ItemsStep> createState() => _ItemsStepState();
}

class _ItemsStepState extends State<_ItemsStep> {
  final _search = TextEditingController();
  String _query = '';
  String? _category;
  bool _selectedOnly = false;
  late String _notes = context.read<CreateDeliveryReceiptCubit>().launch.replacing?.notes ?? '';

  // Search keys folded once per items list, not per keystroke.
  List<ProjectItem>? _keyedFor;
  List<String> _keys = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ProjectItem> _visible(CreateDeliveryReceiptState s) {
    if (!identical(s.items, _keyedFor)) {
      _keyedFor = s.items;
      _keys = [for (final i in s.items) boqSearchKey(i)];
    }
    final words = foldForSearch(
      _query,
    ).split(' ').where((w) => w.isNotEmpty).toList();
    return [
      for (var i = 0; i < s.items.length; i++)
        if ((_category == null || s.items[i].category == _category) &&
            (!_selectedOnly ||
                (s.quantities[s.items[i].id] ?? 0) > 0 ||
                s.invalid.containsKey(s.items[i].id)) &&
            (words.isEmpty || words.every(_keys[i].contains)))
          s.items[i],
    ];
  }

  Future<void> _editNotes() async {
    final ctrl = TextEditingController(text: _notes);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملاحظات السند'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'تظهر أسفل جدول البنود في السند',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) setState(() => _notes = result);
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    final auth = context.read<AuthCubit>().state;
    final repName = auth is AuthAuthenticated ? auth.profile.fullName : '';
    context.read<CreateDeliveryReceiptCubit>().submit(
      repName: repName,
      notes: _notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final categories = [
      for (final c in groupByCategory(state.items))
        if (c.name.isNotEmpty) c.name,
    ];
    final visible = _visible(state);
    final selected = state.selectedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breadcrumb(state: state),
        if (state.droppedFromOriginal > 0)
          _ErrorBanner(
            state.droppedFromOriginal == 1
                ? 'بند واحد من السند السابق لم يعد في عرض المشروع ولن يُنقل'
                : '${state.droppedFromOriginal} بنود من السند السابق لم تعد في عرض المشروع ولن تُنقل',
          ),
        if (state.loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (state.items.isEmpty)
          const Expanded(
            child: _EmptyHint(
              icon: Icons.inventory_2_outlined,
              title: 'لا توجد بنود في هذا المشروع بعد',
              subtitle: 'يضيف المشرف أو المدير بنود العرض من صفحة المشروع',
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: _SearchField(
              controller: _search,
              hint: 'ابحث عن بند',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: Text(
                    selected == 0 ? 'المحدد فقط' : 'المحدد فقط ($selected)',
                  ),
                  selected: _selectedOnly,
                  onSelected: (v) => setState(() => _selectedOnly = v),
                ),
                if (categories.length > 1) ...[
                  ChoiceChip(
                    label: const Text('كل الفئات'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? _EmptyHint(
                    icon: Icons.search_off,
                    title: _selectedOnly
                        ? 'لم تحدد أي بند بعد'
                        : 'لا توجد بنود مطابقة',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final item = visible[i];
                      return _ItemCard(
                        key: ValueKey(item.id),
                        item: item,
                        quantity: state.quantities[item.id] ?? 0,
                        invalidText: state.invalid[item.id],
                        enabled: !state.submitting,
                      );
                    },
                  ),
          ),
          _SubmitBar(
            state: state,
            notes: _notes,
            onEditNotes: _editNotes,
            onSubmit: _submit,
            // The bad row may be scrolled away; this filter shows it.
            onReviewInvalid: () => setState(() {
              _selectedOnly = true;
              _category = null;
            }),
          ),
        ],
      ],
    );
  }
}

class _ItemCard extends StatefulWidget {
  final ProjectItem item;
  final double quantity;
  final String? invalidText;
  final bool enabled;
  const _ItemCard({
    super.key,
    required this.item,
    required this.quantity,
    required this.invalidText,
    required this.enabled,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final _ctrl = TextEditingController(
    text:
        widget.invalidText ??
        (widget.quantity > 0 ? formatQty(widget.quantity) : ''),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final current = parseLocalizedNumber(_ctrl.text) ?? 0;
    final next = (current + delta).clamp(0, double.infinity).toDouble();
    _ctrl.text = next == 0 ? '' : formatQty(next);
    context.read<CreateDeliveryReceiptCubit>().setQuantityText(
      widget.item.id,
      _ctrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final picked = widget.quantity > 0;
    final invalid = widget.invalidText != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: picked ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: invalid
              ? scheme.error
              : (picked ? scheme.primary : scheme.outlineVariant),
          width: picked || invalid ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.itemName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (picked)
                  Icon(Icons.check_circle, color: scheme.primary, size: 22),
              ],
            ),
            if (item.description != null && item.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.description!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'في العرض: ${formatQty(item.quantity)} ${item.unit}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: widget.enabled && (picked || invalid)
                      ? () => _step(-1)
                      : null,
                  icon: const Icon(Icons.remove),
                  tooltip: 'إنقاص',
                ),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _ctrl,
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: theme.textTheme.titleMedium,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onChanged: (v) => context
                        .read<CreateDeliveryReceiptCubit>()
                        .setQuantityText(item.id, v),
                    decoration: InputDecoration(
                      hintText: '0',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      errorText: invalid ? 'رقم غير صحيح' : null,
                      errorStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: widget.enabled ? () => _step(1) : null,
                  icon: const Icon(Icons.add),
                  tooltip: 'زيادة',
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 36),
                  child: Text(item.unit, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  final String notes;
  final VoidCallback onEditNotes;
  final VoidCallback onSubmit;
  final VoidCallback onReviewInvalid;
  const _SubmitBar({
    required this.state,
    required this.notes,
    required this.onEditNotes,
    required this.onSubmit,
    required this.onReviewInvalid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = state.selectedCount;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null) ...[
                Text(state.error!, style: TextStyle(color: scheme.error)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: state.invalid.isNotEmpty ? onReviewInvalid : null,
                      child: Text(
                        state.invalid.isNotEmpty
                            ? 'صحّح الكميات غير الصحيحة — اضغط للعرض'
                            : count == 0
                            ? 'حدد كمية بند واحد على الأقل'
                            : count == 1
                            ? 'بند واحد محدد'
                            : '$count بنود محددة',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: state.invalid.isNotEmpty ? scheme.error : null,
                          decoration: state.invalid.isNotEmpty
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: state.submitting ? null : onEditNotes,
                    icon: Icon(
                      notes.isEmpty
                          ? Icons.note_add_outlined
                          : Icons.sticky_note_2,
                    ),
                    label: Text(notes.isEmpty ? 'ملاحظة' : 'تعديل الملاحظة'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: state.canSubmit ? onSubmit : null,
                  icon: state.submitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    state.submitting
                        ? 'جارٍ الحفظ...'
                        : (context.read<CreateDeliveryReceiptCubit>().launch.isEdit ? 'حفظ التعديل' : 'إنشاء السند'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────

class _FiledView extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  const _FiledView({required this.state});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.read<CreateDeliveryReceiptCubit>().launch.isEdit ? 'تم تعديل السند' : 'تم إنشاء السند',
          ),
          automaticallyImplyLeading: false,
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('تم'),
              ),
            ),
          ],
        ),
        body: PdfPreview(
          build: (_) async => state.pdfBytes!,
          pdfFileName: 'سند_استلام_${state.project?.name ?? ''}.pdf',
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
        ),
      ),
    );
  }
}
