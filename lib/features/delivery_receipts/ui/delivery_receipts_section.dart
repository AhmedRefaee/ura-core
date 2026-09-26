import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/utils/quantity_format.dart';
import '../data/delivery_receipt_repository.dart';
import '../../../core/storage/signed_storage_url.dart';

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
                  for (final r in receipts) DeliveryReceiptTile(receipt: r),
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
  const DeliveryReceiptTile({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    // Timestamps arrive in UTC; the PDF was dated in local time.
    final d = (receipt.deliveredAt ?? receipt.createdAt)?.toLocal();
    final date = d == null ? '' : '${d.year}/${d.month}/${d.day}';
    final itemsSummary = receipt.items
        .map((i) => '${i.itemNameSnapshot} (${formatQty(i.quantityDelivered)} ${i.unitSnapshot})')
        .join('، ');
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text([receipt.project?.name, receipt.entity?.name].whereType<String>().join(' · ')),
      subtitle: Text(
        [date, receipt.rep?.fullName, itemsSummary].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: receipt.pdfUrl == null ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: receipt.pdfUrl == null
          ? null
          : () async {
              final url = await SignedStorageUrl.resolve('delivery-receipts', receipt.pdfUrl);
              if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
    );
  }
}
