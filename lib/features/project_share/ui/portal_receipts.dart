import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/models/delivery_receipt.dart' show ReceiptStatus;
import '../../../shared/utils/quantity_format.dart';
import '../../delivery_receipts/logic/create_delivery_receipt_cubit.dart';
import '../../delivery_receipts/logic/receipt_pdf_builder.dart';
import '../../delivery_receipts/ui/create_delivery_receipt_screen.dart';
import '../../delivery_receipts/ui/receipt_status_chip.dart';
import '../logic/shared_project_cubit.dart';
import '../models/shared_project.dart';

const _kNameKey = 'portal_submitter_name';
const _kPhoneKey = 'portal_submitter_phone';

/// «إنشاء سند» for a link that allows it: asks who is filing (remembered on
/// this device), then opens the same سند screen staff use -- in portal mode,
/// so it files a pending submission instead of a finished سند.
Future<void> startPortalReceipt(BuildContext context, String token, SharedProject project) async {
  final cubit = context.read<SharedProjectCubit>();
  final who = await _askWho(context);
  if (who == null || !context.mounted) return;
  final filed = await openCreateDeliveryReceipt(
    context,
    launch: DeliveryReceiptLaunch.portal(
      PortalLaunch(
        token: token,
        project: project,
        submitterName: who.$1,
        submitterPhone: who.$2,
      ),
    ),
  );
  if (filed) await cubit.refreshReceipts();
}

Future<(String, String?)?> _askWho(BuildContext context) async {
  String name = '';
  String phone = '';
  try {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString(_kNameKey) ?? '';
    phone = prefs.getString(_kPhoneKey) ?? '';
  } catch (_) {
    // No storage (private window): just ask every time.
  }
  if (!context.mounted) return null;
  final nameCtrl = TextEditingController(text: name);
  final phoneCtrl = TextEditingController(text: phone);
  final formKey = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('من يُنشئ السند؟'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameCtrl,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'الاسم'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'أدخل اسمك' : null,
            ),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: const InputDecoration(labelText: 'رقم الجوال (اختياري)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
          },
          child: const Text('متابعة'),
        ),
      ],
    ),
  );
  final n = nameCtrl.text.trim();
  final p = phoneCtrl.text.trim();
  nameCtrl.dispose();
  phoneCtrl.dispose();
  if (ok != true) return null;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNameKey, n);
    await prefs.setString(_kPhoneKey, p);
  } catch (_) {}
  return (n, p.isEmpty ? null : p);
}

/// The submitter's own سندات: pending / approved / rejected. Only those filed
/// through this link -- the server returns nothing else.
class PortalReceiptsSection extends StatelessWidget {
  final SharedProject project;
  final List<SharedReceipt> receipts;
  const PortalReceiptsSection({super.key, required this.project, required this.receipts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (receipts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('سنداتي (${receipts.length})', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final r in receipts) _PortalReceiptCard(project: project, receipt: r),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PortalReceiptCard extends StatelessWidget {
  final SharedProject project;
  final SharedReceipt receipt;
  const _PortalReceiptCard({required this.project, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = receiptStatusStyle(receipt.status);
    final d = receipt.createdAt.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: style.color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReceiptStatusChip(receipt.status),
                const Spacer(),
                Text('${d.year}/${d.month}/${d.day}', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in receipt.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${l.itemName} — ${formatQty(l.quantity)} ${l.unit}'),
              ),
            if (receipt.status != ReceiptStatus.rejected)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => _PortalReceiptPdfScreen(project: project, receipt: receipt)),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('عرض / مشاركة PDF'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds the PDF on the viewer's device from what was filed -- nothing is
/// stored for the submitter, so there is nothing for them to download.
class _PortalReceiptPdfScreen extends StatelessWidget {
  final SharedProject project;
  final SharedReceipt receipt;
  const _PortalReceiptPdfScreen({required this.project, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final byId = {for (final i in project.items) i.id: i};
    return Scaffold(
      appBar: AppBar(title: Text('سند ${project.projectName}')),
      body: PdfPreview(
        build: (_) => buildStoredReceiptPdf(
          entityName: project.entityName ?? '',
          projectName: project.projectName,
          letterheadStored: project.letterheadPath,
          dateMode: receipt.dateMode,
          filedAt: receipt.createdAt,
          customDate: receipt.customDate,
          fullDescription: receipt.fullDescription,
          notes: receipt.notes,
          lines: [
            for (final l in receipt.lines)
              StoredReceiptLine(
                itemName: l.itemName,
                contractDescription: byId[l.projectItemId]?.description,
                unit: l.unit,
                quantity: l.quantity,
                note: l.notes,
              ),
          ],
        ),
        pdfFileName: 'سند_${project.projectName}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
