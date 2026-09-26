import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/utils/quantity_format.dart';
import '../data/delivery_receipt_repository.dart';
import 'create_delivery_receipt_screen.dart';
import 'receipt_actions.dart';

/// The rep's سندات: file one later in the day, detached from any order, and
/// find the ones already filed -- grouped by day, newest first.
class RepDeliveryReceiptsTab extends StatefulWidget {
  const RepDeliveryReceiptsTab({super.key});

  @override
  State<RepDeliveryReceiptsTab> createState() => _RepDeliveryReceiptsTabState();
}

class _RepDeliveryReceiptsTabState extends State<RepDeliveryReceiptsTab> {
  late Future<AppResult<List<DeliveryReceipt>>> _future = _load();

  // The empty state has its own big "سند جديد"; don't show two.
  bool _hasReceipts = false;

  Future<AppResult<List<DeliveryReceipt>>> _load() async {
    final result = await sl<DeliveryReceiptRepository>().fetchMyReceipts();
    final has = result is AppSuccess<List<DeliveryReceipt>> && result.data.isNotEmpty;
    if (mounted && has != _hasReceipts) setState(() => _hasReceipts = has);
    return result;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _create() async {
    if (await openCreateDeliveryReceipt(context)) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سندات الاستلام')),
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
              AppSuccess(:final data) => _ReceiptList(receipts: data, onChanged: _refresh),
            },
          );
        },
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
  const _ReceiptList({required this.receipts, required this.onChanged});

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
      final when = (r.deliveredAt ?? r.createdAt)?.toLocal();
      final label = when == null ? '' : _dayLabel(when);
      if (label != lastDay) {
        rows.add(label);
        lastDay = label;
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
        return _ReceiptCard(receipt: row as DeliveryReceipt, onChanged: onChanged);
      },
    );
  }
}

class _ReceiptCard extends StatefulWidget {
  final DeliveryReceipt receipt;
  final VoidCallback onChanged;
  const _ReceiptCard({required this.receipt, required this.onChanged});

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
