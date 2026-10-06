import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/logic/unit_conversion.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../projects/logic/boq_excel.dart';
import '../../verifier/logic/ai_add_item_cubit.dart';
import '../../verifier/ui/widgets/ai_item_review_view.dart' show AiReviewCopy;
import '../../verifier/ui/widgets/paste_add_item_view.dart';
import '../logic/create_delivery_receipt_cubit.dart';
import '../logic/delivery_receipt_pdf.dart' show packagingOf;
import '../logic/project_item_matching.dart';

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

enum _LeaveChoice { save, discard, cancel }

/// Three full-screen steps -- الجهة، المشروع، البنود -- built for a rep on
/// the move: one hand, big targets, no dropdowns to aim at. Back walks the
/// steps instead of leaving the flow.
class CreateDeliveryReceiptScreen extends StatelessWidget {
  const CreateDeliveryReceiptScreen({super.key});

  static _Step _stepOf(CreateDeliveryReceiptState s) => s.entity == null
      ? _Step.entity
      : (s.project == null ? _Step.project : _Step.items);

  static Future<void> _back(BuildContext context, CreateDeliveryReceiptState s) async {
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    switch (_stepOf(s)) {
      case _Step.entity:
        Navigator.of(context).pop(false);
      case _Step.project:
        if (await _confirmLeaveWithProgress(context, s)) cubit.clearEntity();
      case _Step.items:
        if (await _confirmLeaveWithProgress(context, s)) {
          // A single project was picked automatically; there's no project
          // step to go back to.
          s.projects.length <= 1 ? cubit.clearEntity() : cubit.clearProject();
        }
    }
  }

  /// Stepping back from here would silently throw away any quantities
  /// already typed -- offers to save them as a draft first instead. Returns
  /// whether the caller should proceed with its original step-back; when
  /// the rep chooses to save, this already popped the whole سند flow
  /// itself, so the caller must not also act.
  static Future<bool> _confirmLeaveWithProgress(BuildContext context, CreateDeliveryReceiptState s) async {
    if (s.quantities.isEmpty) return true;
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سيتم فقدان البنود المختارة'),
        content: Text('اخترت ${s.selectedCount} بند. يمكنك حفظها كمسودة لتتابعها لاحقاً، أو تجاهلها.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.cancel),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.discard),
            child: Text('تجاهل', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.save),
            child: const Text('حفظ كمسودة'),
          ),
        ],
      ),
    );
    if (choice == _LeaveChoice.save) {
      await cubit.saveDraft();
      if (context.mounted) Navigator.of(context).pop(false);
      return false;
    }
    return choice == _LeaveChoice.discard;
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
              // Splitting by category only makes sense while picking items,
              // and never while editing -- see submit()'s note on why a
              // replace operation can't split. Kept out of the items step's
              // own toolbar on purpose: that screen is for search, typing
              // quantities, and the calculator -- settings live here instead.
              actions: [
                if (step == _Step.items && !context.read<CreateDeliveryReceiptCubit>().launch.isEdit)
                  _SettingsMenuButton(state: state),
              ],
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

/// The "extra info" realm the items step itself stays free of -- right now
/// just one setting, opened from an icon rather than crowding the main
/// search/quantity/calculator flow.
class _SettingsMenuButton extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  const _SettingsMenuButton({required this.state});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.tune),
      tooltip: 'إعدادات السند',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _SendSettingsDialog(cubit: context.read<CreateDeliveryReceiptCubit>()),
      ),
    );
  }
}

class _SendSettingsDialog extends StatefulWidget {
  final CreateDeliveryReceiptCubit cubit;
  const _SendSettingsDialog({required this.cubit});

  @override
  State<_SendSettingsDialog> createState() => _SendSettingsDialogState();
}

class _SendSettingsDialogState extends State<_SendSettingsDialog> {
  static String _formatCustomDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickCustomDate(DateTime? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) widget.cubit.setCustomDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateDeliveryReceiptCubit, CreateDeliveryReceiptState>(
      bloc: widget.cubit,
      builder: (context, state) {
        final count = state.chosenCategoryCount;
        return AlertDialog(
          title: const Text('إعدادات السند'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Three ways to date the سند: stamped with today (default),
              // left blank for the receiving side to fill in by hand at
              // delivery, or a specific date the creator picks themselves.
              Text('تاريخ السند', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('اليوم'),
                    selected: state.dateMode == ReceiptDateMode.today,
                    onSelected: state.submitting
                        ? null
                        : (_) => widget.cubit.setDateMode(ReceiptDateMode.today),
                  ),
                  ChoiceChip(
                    label: const Text('يدوي عند التسليم'),
                    selected: state.dateMode == ReceiptDateMode.blank,
                    onSelected: state.submitting
                        ? null
                        : (_) => widget.cubit.setDateMode(ReceiptDateMode.blank),
                  ),
                  ChoiceChip(
                    label: Text(
                      state.dateMode == ReceiptDateMode.custom && state.customDate != null
                          ? _formatCustomDate(state.customDate!)
                          : 'تاريخ آخر',
                    ),
                    selected: state.dateMode == ReceiptDateMode.custom,
                    onSelected: state.submitting ? null : (_) => _pickCustomDate(state.customDate),
                  ),
                ],
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('سند منفصل لكل فئة'),
                subtitle: Text(
                  state.splitByCategory && count > 0
                      ? 'سيتم إنشاء $count سند منفصل حسب فئات البنود المختارة'
                      : 'بدلاً من سند واحد يضم كل البنود المختارة، حسب فئات العقد',
                ),
                value: state.splitByCategory,
                onChanged: (v) => widget.cubit.setSplitByCategory(v),
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.save_outlined),
                title: const Text('حفظ كمسودة الآن'),
                subtitle: const Text('يحفظ البنود والكميات المختارة هنا فقط، دون إنشاء السند'),
                enabled: state.quantities.isNotEmpty,
                onTap: () async {
                  await widget.cubit.saveDraft();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('تم حفظ المسودة')));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تم'),
            ),
          ],
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

/// One horizontally scrollable row of filter chips, instead of Wrap, for
/// screens (like the items step's category filters) where wrapping to
/// several rows eats too much vertical space above a long list.
///
/// A plain horizontal SingleChildScrollView/ListView can't be dragged with a
/// mouse -- Flutter's default ScrollBehavior leaves PointerDeviceKind.mouse
/// out of dragDevices and draws no scrollbar -- so on desktop web, chips
/// past the right edge would be simply unreachable. This wraps the list in
/// a ScrollBehavior that restores mouse drag, plus a visible Scrollbar, so
/// scrolling works the same way on touch and with a mouse.
class _FilterChipsRow extends StatefulWidget {
  final List<Widget> chips;
  const _FilterChipsRow({required this.chips});

  @override
  State<_FilterChipsRow> createState() => _FilterChipsRowState();
}

class _FilterChipsRowState extends State<_FilterChipsRow> {
  // Scrollbar needs an explicit controller on a horizontal list -- it isn't
  // eligible for PrimaryScrollController, which only auto-attaches to a
  // vertical scrollable. Without this, debug builds assert on every frame
  // (asserts are stripped in --release, which is why this stayed invisible
  // on the deployed web build).
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ScrollConfiguration(
        behavior: _MouseDragScrollBehavior(),
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            itemCount: widget.chips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => widget.chips[i],
          ),
        ),
      ),
    );
  }
}

class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
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

  /// The بنود a pasted message named, or null when no message is narrowing
  /// the list. Only identifies lines -- quantities are never taken from the
  /// message, since they rarely match the quotation's unit.
  Set<String>? _pastedIds;

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
            (_pastedIds == null || _pastedIds!.contains(s.items[i].id)) &&
            (!_selectedOnly ||
                (s.quantities[s.items[i].id] ?? 0) > 0 ||
                s.invalid.containsKey(s.items[i].id)) &&
            (words.isEmpty || words.every(_keys[i].contains)))
          s.items[i],
    ];
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    context.read<CreateDeliveryReceiptCubit>().submit();
  }

  /// The order flow's paste-a-message entry, pointed at this project's
  /// quotation instead of the inventory. It only finds *which* بنود the
  /// message is about -- the list narrows to them and the rep types each
  /// quantity (or uses the calculator), because a pasted quantity is almost
  /// never in the quotation's unit.
  Future<void> _pasteFromMessage() async {
    FocusManager.instance.primaryFocus?.unfocus();
    var pasted = <String>{};
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<AiAddItemCubit>(),
          child: PasteAddItemView(
            inventory: [for (final i in widget.state.items) i.toMatchable()],
            copy: AiReviewCopy.quotation,
            catalogLabel: 'عرض المشروع',
            onAddInventoryItems: (picked) => pasted = {for (final p in picked) p.item.id},
          ),
        ),
      ),
    );
    if (added == true && pasted.isNotEmpty && mounted) {
      setState(() {
        _pastedIds = pasted;
        _selectedOnly = false;
        _category = null;
        _search.clear();
        _query = '';
      });
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final state = widget.state;
    if (state.selectedCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إلغاء السند؟'),
          content: const Text('لم يتم حفظ السند بعد، وسيتم تجاهل البنود التي حددتها.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء السند'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (context.mounted) Navigator.of(context).pop(false);
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

    // Everything above the submit bar lives in one CustomScrollView -- even
    // the "fixed" header (breadcrumb, search, filter chips) -- so that when
    // the keyboard opens and shrinks the available height, the header and
    // list scroll together instead of being non-flexible Column siblings
    // that can't shrink and overflow once their combined height exceeds
    // what's left. Only the submit bar, a genuinely fixed-height footer,
    // stays outside the scroll area.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _Breadcrumb(state: state)),
              if (state.droppedFromOriginal > 0)
                SliverToBoxAdapter(
                  child: _ErrorBanner(
                    state.droppedFromOriginal == 1
                        ? 'بند واحد من السند السابق لم يعد في عرض المشروع ولن يُنقل'
                        : '${state.droppedFromOriginal} بنود من السند السابق لم تعد في عرض المشروع ولن تُنقل',
                  ),
                ),
              if (state.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyHint(
                    icon: Icons.inventory_2_outlined,
                    title: 'لا توجد بنود في هذا المشروع بعد',
                    subtitle: 'يضيف المشرف أو المدير بنود العرض من صفحة المشروع',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SearchField(
                            controller: _search,
                            hint: 'ابحث عن بند',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste_go),
                          tooltip: 'تحديد البنود من رسالة',
                          onPressed: state.submitting ? null : _pasteFromMessage,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _FilterChipsRow(
                    chips: [
                      FilterChip(
                        label: Text(
                          selected == 0 ? 'المحدد فقط' : 'المحدد فقط ($selected)',
                        ),
                        selected: _selectedOnly,
                        onSelected: (v) => setState(() => _selectedOnly = v),
                      ),
                      if (_pastedIds != null)
                        FilterChip(
                          avatar: const Icon(Icons.content_paste_go, size: 16),
                          label: Text('من الرسالة (${_pastedIds!.length})'),
                          selected: true,
                          onSelected: (_) => setState(() => _pastedIds = null),
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
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyHint(
                      icon: Icons.search_off,
                      title: _selectedOnly
                          ? 'لم تحدد أي بند بعد'
                          : 'لا توجد بنود مطابقة',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final item = visible[i];
                          return _ItemCard(
                            key: ValueKey(item.id),
                            item: item,
                            quantity: state.quantities[item.id] ?? 0,
                            invalidText: state.invalid[item.id],
                            note: state.itemNotes[item.id],
                            enabled: !state.submitting,
                          );
                        },
                        childCount: visible.length,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (!state.loading && state.items.isNotEmpty)
          _SubmitBar(
            state: state,
            onSubmit: _submit,
            onCancel: () => _cancel(context),
            // The bad row may be scrolled away; this filter shows it.
            onReviewInvalid: () => setState(() {
              _selectedOnly = true;
              _category = null;
            }),
          ),
      ],
    );
  }
}

class _ItemCard extends StatefulWidget {
  final ProjectItem item;
  final double quantity;
  final String? invalidText;
  final String? note;
  final bool enabled;
  const _ItemCard({
    super.key,
    required this.item,
    required this.quantity,
    required this.invalidText,
    required this.note,
    required this.enabled,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

// The سند PDF's ملاحظات column is a single fixed-height row (see
// delivery_receipt_pdf.dart's _cell(singleLine: true)) -- capping input
// here means the PDF never has to silently clip what someone typed.
const _kItemNoteMaxLength = 60;

class _ItemCardState extends State<_ItemCard> {
  late final _ctrl = TextEditingController(
    text:
        widget.invalidText ??
        (widget.quantity > 0 ? formatQty(widget.quantity) : ''),
  );
  bool _expanded = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _calculateFromDelivery() async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _ConvertDeliveryDialog(
        itemName: widget.item.itemName,
        registeredUnitLabel: widget.item.unit,
      ),
    );
    if (result != null && mounted) {
      final text = formatQty(result);
      _ctrl.text = text;
      context.read<CreateDeliveryReceiptCubit>().setQuantityText(widget.item.id, text);
    }
  }

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: widget.note ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ملاحظة — ${widget.item.itemName}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: _kItemNoteMaxLength,
          decoration: const InputDecoration(
            hintText: 'تظهر في عمود "ملاحظات" أمام هذا البند في السند',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if ((widget.note ?? '').isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text('إزالة الملاحظة', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
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
    if (result != null && mounted) {
      context.read<CreateDeliveryReceiptCubit>().setItemNote(widget.item.id, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final picked = widget.quantity > 0;
    final invalid = widget.invalidText != null;
    final hasNote = (widget.note ?? '').isNotEmpty;
    final hasDescription = item.description != null && item.description!.isNotEmpty;
    // unitPrice/totalPrice come back null from the server for roles the
    // سند RPC doesn't consider commercial -- see project_item_pricing_visible()
    // in the migration. A rep who can't see pricing just gets no price line.
    final hasPrice = item.unitPrice != null;

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
                  // The big title names the بند and, right alongside it,
                  // the exact packaging text that ends up printed on the
                  // سند itself -- packagingOf() is the same function
                  // create_delivery_receipt_cubit.dart runs before handing
                  // a line to DeliveryReceiptPdf, so this is never out of
                  // sync with what the printed سند actually says.
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      children: [
                        TextSpan(text: item.itemName),
                        if (packagingOf(item.description) != null)
                          TextSpan(
                            text: '  —  ${packagingOf(item.description)}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: widget.enabled ? _editNote : null,
                    icon: Icon(
                      hasNote ? Icons.sticky_note_2 : Icons.note_add_outlined,
                      color: hasNote ? scheme.primary : scheme.outline,
                      size: 20,
                    ),
                    tooltip: hasNote ? 'تعديل الملاحظة' : 'إضافة ملاحظة لهذا البند',
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.outline,
                    ),
                    tooltip: _expanded ? 'إخفاء التفاصيل' : 'عرض الوصف والسعر والكمية في العرض',
                  ),
                ),
                if (picked)
                  Icon(Icons.check_circle, color: scheme.primary, size: 22),
              ],
            ),
            if (_expanded) ...[
              if (hasDescription)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.description!, style: theme.textTheme.bodySmall),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'الوحدة: ${item.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'الكمية الإجمالية في العرض: ${formatQty(item.quantity)} ${item.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
              if (hasPrice)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'سعر العرض: ${formatMoney(item.unitPrice!)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ),
            ],
            if (hasNote)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.sticky_note_2_outlined, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.note!,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: widget.enabled ? _calculateFromDelivery : null,
                  icon: const Icon(Icons.calculate_outlined),
                  tooltip: 'حساب الكمية من التسليم الفعلي',
                ),
                const SizedBox(width: 8),
                Expanded(
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
                      hintText: '0 ${item.unit}',
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// All units offered in a [_UnitWheel] -- every دائرة a بند could be counted
/// in, not just the registered item's own dimension. The registered side
/// can be filled in manually (see [_ConvertDeliveryDialog]) before its
/// dimension is even known, so the wheel can't be pre-filtered the way a
/// delivered-only picker could; a weight-vs-volume mismatch is instead
/// caught and explained once both sides are filled in.
const _wheelUnits = QuantityUnit.values;

/// One "iPhone dial"-style unit picker next to a quantity field -- the shape
/// Ahmed asked for both for what's registered and what was actually
/// delivered: a scrollable wheel on one side, a number field on the other.
class _UnitWheel extends StatefulWidget {
  final QuantityUnit value;
  final ValueChanged<QuantityUnit> onChanged;
  const _UnitWheel({required this.value, required this.onChanged});

  @override
  State<_UnitWheel> createState() => _UnitWheelState();
}

class _UnitWheelState extends State<_UnitWheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: _wheelUnits.indexOf(widget.value),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 96,
      width: 84,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      // Same fix as the category filter chips row: Flutter's default
      // ScrollBehavior leaves PointerDeviceKind.mouse out of dragDevices,
      // so without this a desktop-web mouse simply can't drag the wheel at
      // all -- it looks "stuck" even though touch/trackpad work fine.
      child: ScrollConfiguration(
        behavior: _MouseDragScrollBehavior(),
        child: CupertinoPicker(
          scrollController: _controller,
          itemExtent: 32,
          onSelectedItemChanged: (i) => widget.onChanged(_wheelUnits[i]),
          selectionOverlay: Container(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
              ),
            ),
          ),
          children: [for (final u in _wheelUnits) Center(child: Text(u.label))],
        ),
      ),
    );
  }
}

/// One [_UnitWheel] + unit-size field + شد (per-pack count) field -- what a
/// pack *is*: how big one unit inside it is, and how many of those it
/// holds. Both sides of the conversion are described this way, the عقد's
/// pack and the فاتورة's.
class _WheelQuantityGroup extends StatelessWidget {
  final QuantityUnit unit;
  final ValueChanged<QuantityUnit> onUnitChanged;
  final TextEditingController qtyController;
  final TextEditingController packsController;
  final String qtyLabel;
  final VoidCallback onChanged;
  final bool autofocus;
  const _WheelQuantityGroup({
    required this.unit,
    required this.onUnitChanged,
    required this.qtyController,
    required this.packsController,
    required this.qtyLabel,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UnitWheel(
          value: unit,
          onChanged: (u) {
            onUnitChanged(u);
            onChanged();
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: qtyController,
                autofocus: autofocus,
                keyboardType: numeric,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: qtyLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: packsController,
                keyboardType: numeric,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: 'شد',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Both sides of a سند conversion, entered entirely by hand, every time:
/// what one registered unit is per the عقد, and what the فاتورة actually
/// says was delivered. Nothing here is detected or remembered from a
/// previous سند -- different deliveries of the exact same بند can come in
/// different شد (a dozen a carton once, two dozen another time), so neither
/// side is ever assumed. Nothing reaches the quantity field until "تأكيد"
/// is pressed; the computed number is only ever a preview until then.
class _ConvertDeliveryDialog extends StatefulWidget {
  final String itemName;
  final String registeredUnitLabel;

  const _ConvertDeliveryDialog({
    required this.itemName,
    required this.registeredUnitLabel,
  });

  @override
  State<_ConvertDeliveryDialog> createState() => _ConvertDeliveryDialogState();
}

class _ConvertDeliveryDialogState extends State<_ConvertDeliveryDialog> {
  // Both sides describe a pack the same way, because that's what a pack
  // actually is: the size of one unit inside it (500 جم, 1.75 كجم, 2 لتر)
  // and how many of those the pack holds (شد). The عقد's pack and the
  // فاتورة's pack are then just two numbers in the same base unit, and the
  // rate between them is one division.

  // من العقد -- what one registered unit (e.g. 1 كرتون) amounts to.
  final _regQty = TextEditingController();
  final _regPacks = TextEditingController(text: '1');
  QuantityUnit _regUnit = QuantityUnit.kilogram;

  // من الفاتورة -- what one *bought* pack amounts to.
  final _boughtQty = TextEditingController();
  final _boughtPacks = TextEditingController(text: '1');
  QuantityUnit _boughtUnit = QuantityUnit.kilogram;

  /// How many of those bought packs were actually bought -- the last
  /// multiplication, applied to the rate once it's known.
  final _count = TextEditingController();

  @override
  void dispose() {
    _regQty.dispose();
    _regPacks.dispose();
    _boughtQty.dispose();
    _boughtPacks.dispose();
    _count.dispose();
    super.dispose();
  }

  RegisteredPackaging? get _registered => _packOf(_regQty, _regPacks, _regUnit);

  RegisteredPackaging? get _boughtPack => _packOf(_boughtQty, _boughtPacks, _boughtUnit);

  static RegisteredPackaging? _packOf(
    TextEditingController size,
    TextEditingController packs,
    QuantityUnit unit,
  ) {
    final s = parseLocalizedNumber(size.text);
    final p = parseLocalizedNumber(packs.text);
    if (s == null || s <= 0 || p == null || p <= 0) return null;
    return RegisteredPackaging(packSize: s, packCount: p, baseUnit: unit);
  }

  /// What ONE bought pack is worth in registered units -- shown as soon as
  /// both packs are described, before the count is even typed, so the
  /// multiplication behind the final number is never hidden.
  double? get _rate {
    final registered = _registered;
    final bought = _boughtPack;
    if (registered == null || bought == null) return null;
    return calculateReceiptQuantity(
      registered: registered,
      deliveredQuantity: bought.packSize,
      deliveredUnit: bought.baseUnit,
      deliveredPackCount: bought.packCount,
    );
  }

  double? get _result {
    final rate = _rate;
    final count = parseLocalizedNumber(_count.text);
    if (rate == null || count == null || count <= 0) return null;
    return rate * count;
  }

  /// Why there's no number yet, or the dimension mismatch that's stopping
  /// one -- shown in place of the result instead of a bare "enter a value".
  String get _statusText {
    if (_registered == null) return 'أدخل بيانات العقد أولاً';
    if (_boughtPack == null) return 'أدخل بيانات العبوة المشتراة';
    if (_rate == null) return 'لا يمكن التحويل بين وزن وحجم -- تحقق من الوحدتين';
    return 'أدخل عدد العبوات المشتراة لمعاينة الناتج';
  }

  /// More decimal places than formatQty's 2 -- a per-unit rate is often a
  /// small fraction (e.g. 1 delivered كجم against a 40kg registered بند is
  /// 0.025), and rounding that to 2 decimals would show "0.03": a rate
  /// nearly 20% off from what it actually is.
  static String _formatRate(double v) {
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;
    final rate = _rate;
    final isSized = RegExp(r'^\s*[0-9٠-٩]').hasMatch(widget.registeredUnitLabel);

    return AlertDialog(
      title: Text('حساب الكمية — ${widget.itemName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('من العقد', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _WheelQuantityGroup(
              unit: _regUnit,
              onUnitChanged: (u) => _regUnit = u,
              qtyController: _regQty,
              packsController: _regPacks,
              qtyLabel: '1 ${widget.registeredUnitLabel} =',
              autofocus: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('من الفاتورة', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _WheelQuantityGroup(
              unit: _boughtUnit,
              onUnitChanged: (u) => _boughtUnit = u,
              qtyController: _boughtQty,
              packsController: _boughtPacks,
              qtyLabel: '1 عبوة مشتراة =',
              onChanged: () => setState(() {}),
            ),
            if (rate != null) ...[
              const Divider(height: 24),
              Text(
                'معدل التحويل: 1 عبوة مشتراة = ${_formatRate(rate)}'
                '${isSized ? '' : ' ${widget.registeredUnitLabel}'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _count,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'كم عبوة اشتريت؟',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              result == null
                  ? _statusText
                  // The registered unit's own name already states its size
                  // (e.g. "40 كجم") when that's what was typed in for it --
                  // repeating it after the number would double it up
                  // ("= 12 40 كجم"), so only echo it when it's a plain name.
                  : isSized
                      ? '= ${formatQty(result)}'
                      : '= ${formatQty(result)} ${widget.registeredUnitLabel}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: result == null ? scheme.outline : scheme.primary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: result == null ? null : () => Navigator.pop(context, result),
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}

class _SubmitBar extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onReviewInvalid;
  const _SubmitBar({
    required this.state,
    required this.onSubmit,
    required this.onCancel,
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
              GestureDetector(
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
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: state.submitting ? null : onCancel,
                        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                        icon: const Icon(Icons.close),
                        label: const Text('إلغاء'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
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
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          state.submitting
                              ? 'جارٍ الحفظ...'
                              : (context.read<CreateDeliveryReceiptCubit>().launch.isEdit ? 'تأكيد التعديل' : 'تأكيد وإنشاء السند'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    final hasMore = state.remainingReceipts.isNotEmpty;
    final total = state.totalReceiptsThisSubmit;
    final position = total - state.remainingReceipts.length;
    final category = state.currentCategoryLabel;

    // Splitting by category produced more than one سند this submit --
    // advance to the next one instead of leaving the flow; only the very
    // last one actually closes it.
    void proceed() => hasMore ? cubit.advanceToNextReceipt() : Navigator.of(context).pop(true);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) proceed();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text([
            cubit.launch.isEdit ? 'تم تعديل السند' : 'تم إنشاء السند',
            if (total > 1) '($position من $total)',
            if (total > 1 && (category?.isNotEmpty ?? false)) '— $category',
          ].join(' ')),
          automaticallyImplyLeading: false,
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton(
                onPressed: proceed,
                child: Text(hasMore ? 'التالي' : 'تم'),
              ),
            ),
          ],
        ),
        body: PdfPreview(
          build: (_) async => state.pdfBytes!,
          pdfFileName: 'سند_استلام_${state.project?.name ?? ''}'
              '${(category?.isNotEmpty ?? false) ? '_$category' : ''}.pdf',
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
        ),
      ),
    );
  }
}
