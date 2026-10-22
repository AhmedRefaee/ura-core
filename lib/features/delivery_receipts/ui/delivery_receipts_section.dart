import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/utils/quantity_format.dart';
import '../data/delivery_receipt_repository.dart';
import 'receipt_actions.dart';
import 'receipt_status_chip.dart';

/// Read-only list of سندات attached to an order or a project. Shown inside
/// the record a role already opens, never as its own top-level section.
class DeliveryReceiptsSection extends StatefulWidget {
  final String? orderId;
  final String? projectId;

  /// Hides the whole section when there is nothing to show, so order screens
  /// don't grow an empty card on every order that never got a سند.
  final bool hideWhenEmpty;

  const DeliveryReceiptsSection.forOrder(String this.orderId, {super.key, this.hideWhenEmpty = true})
      : projectId = null;

  const DeliveryReceiptsSection.forProject(String this.projectId, {super.key, this.hideWhenEmpty = false})
      : orderId = null;

  @override
  State<DeliveryReceiptsSection> createState() => DeliveryReceiptsSectionState();
}

class DeliveryReceiptsSectionState extends State<DeliveryReceiptsSection> {
  late Future<AppResult<List<DeliveryReceipt>>> _future = _load();

  Future<AppResult<List<DeliveryReceipt>>> _load() {
    final repo = sl<DeliveryReceiptRepository>();
    return widget.orderId != null
        ? repo.fetchReceiptsForOrder(widget.orderId!)
        : repo.fetchReceiptsForProject(widget.projectId!);
  }

  void reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppResult<List<DeliveryReceipt>>>(
      future: _future,
      builder: (context, snap) {
        final result = snap.data;
        if (result == null) {
          return widget.hideWhenEmpty
              ? const SizedBox.shrink()
              : const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
        }
        final receipts = switch (result) {
          AppSuccess(:final data) => data,
          AppFailure() => const <DeliveryReceipt>[],
        };
        if (receipts.isEmpty && widget.hideWhenEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('سندات الاستلام', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      Text('${receipts.length}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (result is AppFailure<List<DeliveryReceipt>>)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(result.error.message, style: TextStyle(color: theme.colorScheme.error)),
                  )
                else if (receipts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد سندات بعد'),
                  )
                else
                  for (final r in receipts) DeliveryReceiptTile(receipt: r, onChanged: reload),
              ],
            ),
          ),
        );
      },
    );
  }
}

class DeliveryReceiptTile extends StatelessWidget {
  final DeliveryReceipt receipt;

  /// After the creator edits or deletes it from the ⋮ menu.
  final VoidCallback? onChanged;
  const DeliveryReceiptTile({super.key, required this.receipt, this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Timestamps arrive in UTC; the PDF was dated in local time.
    final d = (receipt.deliveredAt ?? receipt.createdAt)?.toLocal();
    final date = d == null ? '' : '${d.year}/${d.month}/${d.day}';
    final itemsSummary = receipt.items
        .map((i) => '${i.itemNameSnapshot} (${formatQty(i.quantityDelivered)} ${i.unitSnapshot})')
        .join('، ');
    // A سند an outside entity filed through a share link is set apart: it
    // carries who sent it and, until approved, an amber tint and a
    // pending badge, so it can't be mistaken for one of ours.
    final portal = receipt.isPortalSubmission;
    final pending = receipt.status == ReceiptStatus.pending;
    final author = portal
        ? 'من الجهة: ${[receipt.submitterName, receipt.submitterPhone].whereType<String>().where((s) => s.isNotEmpty).join(' · ')}'
        : receipt.rep?.fullName;
    final style = receiptStatusStyle(receipt.status);
    return Container(
      color: pending ? style.color.withValues(alpha: 0.08) : null,
      child: ListTile(
        leading: Icon(
          pending ? Icons.hourglass_top_rounded : (portal ? Icons.business_outlined : Icons.picture_as_pdf_outlined),
          color: pending ? style.color : (portal ? Theme.of(context).colorScheme.tertiary : null),
        ),
        title: Text([receipt.project?.name, receipt.entity?.name].whereType<String>().join(' · ')),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (portal)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.business_outlined, size: 14),
                      label: const Text('من الجهة'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    ReceiptStatusChip(receipt.status),
                  ],
                ),
              ),
            Text(
              [date, author, itemsSummary].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: onChanged != null && (canManageReceipt(context, receipt) || pending)
            ? ReceiptMenuButton(receipt: receipt, onChanged: onChanged!)
            : (receipt.pdfUrl == null ? null : const Icon(Icons.open_in_new, size: 18)),
        onTap: receipt.pdfUrl == null
            ? (pending && onChanged != null ? () async { if (await approveReceipt(context, receipt)) onChanged!(); } : null)
            : () => openReceiptPdf(context, receipt),
      ),
    );
  }
}
