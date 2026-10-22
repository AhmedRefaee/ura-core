import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/models/delivery_receipt_draft.dart';
import '../../../shared/utils/quantity_format.dart';
import '../data/delivery_receipt_draft_repository.dart';
import '../data/delivery_receipt_repository.dart';
import '../logic/create_delivery_receipt_cubit.dart' show DeliveryReceiptLaunch;
import '../logic/receipt_creator_filter.dart';
import 'create_delivery_receipt_screen.dart';
import 'receipt_actions.dart';

/// The current user's سندات: file one later in the day, detached from any
/// order, and find the ones already filed -- grouped by day, newest first.
/// Shared by reps and verifiers; "mine" is whoever is signed in, not a
/// hardcoded role. Verifiers (and admins) can also switch to everyone's, or
/// one person's, and edit/delete any of them -- see managesAllReceipts().
class DeliveryReceiptsTab extends StatefulWidget {
  const DeliveryReceiptsTab({super.key});

  @override
  State<DeliveryReceiptsTab> createState() => _DeliveryReceiptsTabState();
}

class _DeliveryReceiptsTabState extends State<DeliveryReceiptsTab> {
  late final bool _managesAll = managesAllReceipts(context);
  late Future<AppResult<List<DeliveryReceipt>>> _future = _load();
  List<DeliveryReceiptDraft> _drafts = sl<DeliveryReceiptDraftRepository>().list();
  ReceiptCreatorFilter _filter = const MineFilter();
  String? _entityId;
  DateTimeRange? _dates;
  ReceiptSort _sort = ReceiptSort.newest;
  final String? _myId = Supabase.instance.client.auth.currentUser?.id;

  // The empty state has its own big "سند جديد"; don't show two.
  bool _hasReceipts = false;

  Future<AppResult<List<DeliveryReceipt>>> _load() async {
    final repo = sl<DeliveryReceiptRepository>();
    final result = await (_managesAll ? repo.fetchVisibleReceipts() : repo.fetchMyReceipts());
    final has = result is AppSuccess<List<DeliveryReceipt>> && result.data.isNotEmpty;
    if (mounted && has != _hasReceipts) setState(() => _hasReceipts = has);
    return result;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  void _reloadDrafts() => setState(() => _drafts = sl<DeliveryReceiptDraftRepository>().list());

  Future<void> _create() async {
    // Whether or not a سند actually got filed, the drafts list may have
    // changed (one saved, resumed, or deleted) during that visit.
    if (await openCreateDeliveryReceipt(context)) _refresh();
    _reloadDrafts();
  }

  Future<void> _resumeDraft(DeliveryReceiptDraft draft) async {
    final messenger = ScaffoldMessenger.of(context);
    DeliveryReceipt? replacing;
    final replacesId = draft.replacesReceiptId;
    if (replacesId != null) {
      // Looked up fresh: the سند may have been deleted or replaced since
      // the draft was saved.
      switch (await sl<DeliveryReceiptRepository>().fetchReceipt(replacesId)) {
        case AppSuccess(:final data):
          replacing = data;
          if (data == null) {
            messenger.showSnackBar(const SnackBar(
              content: Text('السند الأصلي حُذف أو استُبدل — ستُنشئ هذه المسودة سنداً جديداً'),
            ));
          }
        case AppFailure(:final error):
          // Opening anyway would file it as a new سند next to the original.
          messenger.showSnackBar(SnackBar(content: Text(error.message)));
          return;
      }
    }
    if (!mounted) return;
    final launch = DeliveryReceiptLaunch.resumeDraft(draft, replacing: replacing);
    if (await openCreateDeliveryReceipt(context, launch: launch)) {
      _refresh();
    }
    _reloadDrafts();
  }

  Future<void> _deleteDraft(DeliveryReceiptDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المسودة؟'),
        content: Text('سيتم حذف مسودة "${draft.projectName}" نهائياً — لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('حذف', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await sl<DeliveryReceiptDraftRepository>().delete(draft.id);
      _reloadDrafts();
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = _dates;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: range,
      helpText: 'تاريخ السندات',
      saveText: 'تطبيق',
    );
    if (picked != null) setState(() => _dates = picked);
  }

  static String _dateLabel(DateTimeRange r) {
    final thisYear = DateTime.now().year;
    String d(DateTime x) => x.year == thisYear ? '${x.day}/${x.month}' : '${x.day}/${x.month}/${x.year}';
    return DateUtils.isSameDay(r.start, r.end) ? d(r.start) : '${d(r.start)} – ${d(r.end)}';
  }

  void _clearFilters() => setState(() {
        _entityId = null;
        _dates = null;
        if (_managesAll) _filter = const EveryoneFilter();
      });

  /// Filters over the list: who filed it (verifiers/admins only), which
  /// entity, which days -- then the list for that choice.
  Widget _filteredList(List<DeliveryReceipt> all) {
    final creators = receiptCreators(all, _myId);
    final entities = receiptEntities(all);
    final hasLinks = all.any((r) => r.isPortalSubmission);
    // A choice can drop out of the list (its last سند deleted elsewhere).
    final filter = switch (_filter) {
      PersonFilter(:final userId) when !creators.any((c) => c.id == userId) => const MineFilter(),
      ShareLinkFilter() when !hasLinks => const MineFilter(),
      final f => f,
    };
    final entityId = entities.any((e) => e.id == _entityId) ? _entityId : null;
    final dates = _dates;
    final shown = filterReceiptsByEntityAndDate(
      _managesAll ? filterReceiptsByCreator(all, filter, _myId) : all,
      entityId: entityId,
      from: dates?.start,
      to: dates?.end,
    );
    const dense = InputDecoration(border: OutlineInputBorder(), isDense: true);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_managesAll) ...[
                DropdownButtonFormField<ReceiptCreatorFilter>(
                  // initialValue only seeds the field; the key makes a filter
                  // changed from outside (fallback, "مسح") show up.
                  key: ValueKey(filter),
                  initialValue: filter,
                  isExpanded: true,
                  decoration: dense.copyWith(labelText: 'المنشئ', prefixIcon: const Icon(Icons.person_search_outlined)),
                  items: [
                    const DropdownMenuItem(value: MineFilter(), child: Text('سنداتي')),
                    const DropdownMenuItem(value: EveryoneFilter(), child: Text('الجميع')),
                    for (final c in creators)
                      DropdownMenuItem(value: PersonFilter(c.id), child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    if (hasLinks) const DropdownMenuItem(value: ShareLinkFilter(), child: Text('عبر رابط الجهة')),
                  ],
                  onChanged: (f) => setState(() => _filter = f ?? const MineFilter()),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('entity:$entityId'),
                      initialValue: entityId,
                      isExpanded: true,
                      decoration: dense.copyWith(labelText: 'الجهة', prefixIcon: const Icon(Icons.business_outlined)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل الجهات')),
                        for (final e in entities)
                          DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (id) => setState(() => _entityId = id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: dates == null
                        ? OutlinedButton.icon(
                            onPressed: _pickDates,
                            icon: const Icon(Icons.date_range_outlined),
                            label: const Text('كل التواريخ'),
                          )
                        : InputChip(
                            avatar: const Icon(Icons.date_range, size: 18),
                            // Scaled down, never cut off: a date must stay whole.
                            label: FittedBox(fit: BoxFit.scaleDown, child: Text(_dateLabel(dates))),
                            onPressed: _pickDates,
                            onDeleted: () => setState(() => _dates = null),
                            deleteButtonTooltipMessage: 'إلغاء تصفية التاريخ',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? _Scrollable(
                  child: _Message(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'لا توجد سندات لهذا الاختيار',
                    subtitle: _managesAll ? 'غيّر عوامل التصفية أو اعرض سندات الجميع' : 'غيّر الجهة أو التاريخ',
                    action: OutlinedButton(onPressed: _clearFilters, child: const Text('مسح التصفية')),
                  ),
                )
              : _ReceiptList(
                  receipts: sortReceipts(shown, _sort),
                  onChanged: _refresh,
                  showAuthor: _managesAll && filter is! MineFilter,
                  groupByDay: _sort.groupsByDay,
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سندات الاستلام'),
        actions: [
          PopupMenuButton<ReceiptSort>(
            tooltip: 'ترتيب: ${_sort.label}',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in ReceiptSort.values)
                CheckedPopupMenuItem(value: s, checked: s == _sort, child: Text(s.label)),
            ],
          ),
        ],
      ),
      floatingActionButton: _hasReceipts
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('سند جديد'),
            )
          : null,
      body: FutureBuilder<AppResult<List<DeliveryReceipt>>>(
        future: _future,
        builder: (context, snap) {
          final result = snap.data;
          if (result == null) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: _refresh,
            child: Column(
              children: [
                if (_drafts.isNotEmpty)
                  _DraftsSection(drafts: _drafts, onResume: _resumeDraft, onDelete: _deleteDraft),
                Expanded(
                  child: switch (result) {
                    AppFailure(:final error) => _Scrollable(
                        child: _Message(
                          icon: Icons.cloud_off_outlined,
                          title: 'تعذر تحميل السندات',
                          subtitle: error.message,
                          action: OutlinedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ),
                      ),
                    AppSuccess(:final data) when data.isEmpty => _Scrollable(
                        child: _Message(
                          icon: Icons.receipt_long_outlined,
                          title: 'لا توجد سندات بعد',
                          subtitle: 'أنشئ سند استلام لأي تسليم — من الطلب بعد تسليمه، أو من هنا في أي وقت',
                          action: FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add),
                            label: const Text('سند جديد'),
                          ),
                        ),
                      ),
                    AppSuccess(:final data) => _filteredList(data),
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Drafts saved on this device, newest first -- see
/// CreateDeliveryReceiptCubit.saveDraft(). Shown above the filed سندات so a
/// paused سند is never one screen harder to find than a finished one.
class _DraftsSection extends StatelessWidget {
  final List<DeliveryReceiptDraft> drafts;
  final ValueChanged<DeliveryReceiptDraft> onResume;
  final ValueChanged<DeliveryReceiptDraft> onDelete;
  const _DraftsSection({required this.drafts, required this.onResume, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('مسودات', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text('${drafts.length}', style: theme.textTheme.bodySmall),
            ],
          ),
          for (final d in drafts)
            _DraftTile(draft: d, onResume: () => onResume(d), onDelete: () => onDelete(d)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  final DeliveryReceiptDraft draft;
  final VoidCallback onResume;
  final VoidCallback onDelete;
  const _DraftTile({required this.draft, required this.onResume, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final saved = draft.savedAt.toLocal();
    final when = '${saved.year}/${saved.month}/${saved.day} '
        '${saved.hour.toString().padLeft(2, '0')}:${saved.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(draft.isEdit ? Icons.edit_outlined : Icons.edit_note),
        title: Text(
          draft.isEdit ? 'تعديل: ${draft.projectName}' : draft.projectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${draft.entityName} · ${draft.itemCount == 1 ? 'بند واحد' : '${draft.itemCount} بنود'} · $when',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onResume,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'حذف المسودة',
          onPressed: onDelete,
        ),
      ),
    );
  }
}

/// Lets pull-to-refresh work on empty and error states too.
class _Scrollable extends StatelessWidget {
  final Widget child;
  const _Scrollable({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: c.maxHeight), child: child),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;
  const _Message({required this.icon, required this.title, required this.subtitle, required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(icon, size: 40, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}

class _ReceiptList extends StatelessWidget {
  final List<DeliveryReceipt> receipts;
  final VoidCallback onChanged;

  /// Name who filed each سند -- when the list isn't just the user's own.
  final bool showAuthor;

  /// Day headers over the cards (date orders). Off, each card carries its
  /// own date instead.
  final bool groupByDay;
  const _ReceiptList({
    required this.receipts,
    required this.onChanged,
    this.showAuthor = false,
    this.groupByDay = true,
  });

  static const _weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${_weekdays[d.weekday - 1]} ${d.day}/${d.month}${d.year != now.year ? '/${d.year}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    // Flatten into headers + cards so the list stays lazy.
    final rows = <Object>[];
    String? lastDay;
    for (final r in receipts) {
      if (groupByDay) {
        final when = (r.deliveredAt ?? r.createdAt)?.toLocal();
        final label = when == null ? '' : _dayLabel(when);
        if (label != lastDay) {
          rows.add(label);
          lastDay = label;
        }
      }
      rows.add(r);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
            child: Text(row, style: Theme.of(context).textTheme.titleSmall),
          );
        }
        return _ReceiptCard(
          receipt: row as DeliveryReceipt,
          onChanged: onChanged,
          showAuthor: showAuthor,
          showDate: !groupByDay,
        );
      },
    );
  }
}

class _ReceiptCard extends StatefulWidget {
  final DeliveryReceipt receipt;
  final VoidCallback onChanged;
  final bool showAuthor;

  /// No day header above this card, so it shows its date itself.
  final bool showDate;
  const _ReceiptCard({required this.receipt, required this.onChanged, this.showAuthor = false, this.showDate = false});

  @override
  State<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends State<_ReceiptCard> {
  bool _opening = false;

  Future<void> _openPdf() async {
    setState(() => _opening = true);
    await openReceiptPdf(context, widget.receipt);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receipt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final when = (r.deliveredAt ?? r.createdAt)?.toLocal();
    final time = when == null
        ? ''
        : '${when.hour == 0 ? 12 : (when.hour > 12 ? when.hour - 12 : when.hour)}:${when.minute.toString().padLeft(2, '0')} ${when.hour < 12 ? 'ص' : 'م'}';
    final preview = r.items.take(3).map((i) => '${i.itemNameSnapshot} × ${formatQty(i.quantityDelivered)}').join('، ');
    final more = r.items.length > 3 ? ' +${r.items.length - 3}' : '';
    final hasPdf = r.pdfUrl != null;

    Widget pill(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(text, style: theme.textTheme.labelSmall),
          ]),
        );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasPdf && !_opening ? _openPdf : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.project?.name ?? 'مشروع',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(r.entity?.name ?? '',
                        style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (widget.showAuthor)
                        r.isPortalSubmission
                            ? pill(Icons.link, r.submitterName ?? 'رابط الجهة')
                            : pill(Icons.person_outline, isOwnReceipt(r) ? 'أنا' : (r.rep?.fullName ?? 'مستخدم')),
                      if (r.status == ReceiptStatus.pending) pill(Icons.hourglass_top, 'بانتظار الاعتماد'),
                      if (widget.showDate && when != null)
                        pill(Icons.event, '${when.day}/${when.month}/${when.year}'),
                      if (time.isNotEmpty) pill(Icons.schedule, time),
                      pill(Icons.inventory_2_outlined, r.items.length == 1 ? 'بند واحد' : '${r.items.length} بنود'),
                      if (r.orderId != null) pill(Icons.link, 'من طلب'),
                    ]),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('$preview$more',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_opening)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.picture_as_pdf, color: hasPdf ? scheme.primary : scheme.outline),
                    ),
                  ReceiptMenuButton(receipt: r, onChanged: widget.onChanged),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
