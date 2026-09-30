import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/storage/signed_storage_url.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../data/delivery_receipt_repository.dart';
import '../logic/create_delivery_receipt_cubit.dart';
import 'create_delivery_receipt_screen.dart';

/// Whether the signed-in user filed this سند (the server also allows admins;
/// the menu is only offered to the creator).
bool isOwnReceipt(DeliveryReceipt r) => r.repId == Supabase.instance.client.auth.currentUser?.id;

Future<void> openReceiptPdf(BuildContext context, DeliveryReceipt r) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = await SignedStorageUrl.resolve('delivery-receipts', r.pdfUrl);
  if (url == null) {
    messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح ملف السند')));
    return;
  }
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Opens the سند flow pre-filled from [r]; filing replaces it. True if saved.
Future<bool> editReceipt(BuildContext context, DeliveryReceipt r) =>
    openCreateDeliveryReceipt(context, launch: DeliveryReceiptLaunch.edit(r));

/// Confirms, then archives [r]. True if it was deleted.
Future<bool> deleteReceipt(BuildContext context, DeliveryReceipt r) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
      title: const Text('حذف السند؟'),
      content: Text(
        'سيُحذف سند ${r.project?.name ?? ''} لـ ${r.entity?.name ?? ''} من القوائم. '
        'إن كان العميل قد وقّع نسخة منه، أنشئ سنداً بديلاً بدلاً من الحذف.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final result = await sl<DeliveryReceiptRepository>().deleteDeliveryReceipt(r.id);
  switch (result) {
    case AppSuccess():
      messenger.showSnackBar(const SnackBar(content: Text('تم حذف السند')));
      return true;
    case AppFailure(:final error):
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
  }
}

enum ReceiptAction { open, edit, delete }

/// ⋮ menu for a سند. Edit/delete appear only for its creator.
class ReceiptMenuButton extends StatelessWidget {
  final DeliveryReceipt receipt;

  /// Called after a successful edit or delete, so the list can refresh.
  final VoidCallback onChanged;

  const ReceiptMenuButton({super.key, required this.receipt, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final own = isOwnReceipt(receipt);
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<ReceiptAction>(
      tooltip: 'خيارات السند',
      onSelected: (action) async {
        switch (action) {
          case ReceiptAction.open:
            await openReceiptPdf(context, receipt);
          case ReceiptAction.edit:
            if (await editReceipt(context, receipt)) onChanged();
          case ReceiptAction.delete:
            if (context.mounted && await deleteReceipt(context, receipt)) onChanged();
        }
      },
      itemBuilder: (_) => [
        if (receipt.pdfUrl != null)
          const PopupMenuItem(
            value: ReceiptAction.open,
            child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('فتح السند')),
          ),
        if (own) ...[
          const PopupMenuItem(
            value: ReceiptAction.edit,
            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل')),
          ),
          PopupMenuItem(
            value: ReceiptAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: error),
              title: Text('حذف', style: TextStyle(color: error)),
            ),
          ),
        ],
      ],
    );
  }
}
