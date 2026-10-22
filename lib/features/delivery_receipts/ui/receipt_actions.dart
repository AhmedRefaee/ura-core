import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/storage/signed_storage_url.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/models/profile.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../projects/data/project_repository.dart';
import '../data/delivery_receipt_repository.dart';
import '../data/delivery_receipt_storage_service.dart';
import '../logic/create_delivery_receipt_cubit.dart';
import '../logic/receipt_pdf_builder.dart';
import 'create_delivery_receipt_screen.dart';

/// Whether the signed-in user filed this سند.
bool isOwnReceipt(DeliveryReceipt r) =>
    r.repId != null && r.repId == Supabase.instance.client.auth.currentUser?.id;

/// Verifiers and admins manage every سند of their org; anyone else only
/// their own. Mirrors delete_delivery_receipt / create_delivery_receipt.
bool managesAllReceipts(BuildContext context) {
  final auth = context.read<AuthCubit>().state;
  final role = auth is AuthAuthenticated ? auth.profile.role : null;
  return role == UserRole.verifier || role == UserRole.admin;
}

/// Edit/delete are offered on approved سندات the user may manage; a pending
/// submission is approved or rejected instead.
bool canManageReceipt(BuildContext context, DeliveryReceipt r) =>
    r.status == ReceiptStatus.approved && (isOwnReceipt(r) || managesAllReceipts(context));

Future<void> openReceiptPdf(BuildContext context, DeliveryReceipt r) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = await SignedStorageUrl.resolve('delivery-receipts', r.pdfUrl);
  if (url == null) {
    messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح ملف السند')));
    return;
  }
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Downloads the سند's PDF and hands the bytes to the platform share sheet,
/// so the recipient gets the file itself rather than a link that expires.
Future<void> shareReceiptPdf(BuildContext context, DeliveryReceipt r) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final bounds = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final url = await SignedStorageUrl.resolve('delivery-receipts', r.pdfUrl);
  if (url == null) {
    messenger.showSnackBar(const SnackBar(content: Text('تعذر مشاركة ملف السند')));
    return;
  }
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final project = (r.project?.name ?? '').replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
    final name = project.isEmpty ? 'سند.pdf' : 'سند $project.pdf';
    final file = XFile.fromData(response.bodyBytes, mimeType: 'application/pdf', name: name);
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: [name], sharePositionOrigin: bounds),
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('تعذر مشاركة ملف السند')));
  }
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

/// Reviews a سند an outside entity filed through a share link and, on
/// approval, generates its PDF (the submitter never uploads one) and makes it
/// official. True if it was approved.
Future<bool> approveReceipt(BuildContext context, DeliveryReceipt r) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('اعتماد السند؟'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مقدَّم من: ${[r.submitterName, r.submitterPhone].whereType<String>().where((s) => s.isNotEmpty).join(' · ')}'),
            const SizedBox(height: 8),
            for (final i in r.items)
              Text('• ${i.itemNameSnapshot} — ${formatQty(i.quantityDelivered)} ${i.unitSnapshot}'),
            if (r.notes?.isNotEmpty ?? false) ...[const SizedBox(height: 8), Text('ملاحظات: ${r.notes}')],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    final itemsResult = await sl<ProjectRepository>().fetchProjectItems(r.projectId);
    final byId = <String, ProjectItem>{
      if (itemsResult is AppSuccess<List<ProjectItem>>) for (final i in itemsResult.data) i.id: i,
    };
    final meta = r.submissionMeta ?? const {};
    final pdf = await buildStoredReceiptPdf(
      entityName: r.entity?.name ?? '',
      projectName: r.project?.name ?? '',
      letterheadStored: r.letterheadImageUrlSnapshot,
      dateMode: meta['date_mode'] as String? ?? 'today',
      filedAt: r.createdAt ?? DateTime.now(),
      customDate: switch (meta['custom_date']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      fullDescription: meta['full_description'] as bool? ?? false,
      categoryTitle: meta['category'] as String?,
      notes: r.notes,
      lines: [
        for (final i in r.items)
          StoredReceiptLine(
            itemName: i.itemNameSnapshot,
            contractDescription: byId[i.projectItemId]?.description,
            unit: i.unitSnapshot,
            quantity: i.quantityDelivered,
            note: i.notes,
          ),
      ],
    );
    final upload = await sl<DeliveryReceiptStorageService>().uploadPdf(pdf);
    final String path;
    switch (upload) {
      case AppSuccess(:final data):
        path = data;
      case AppFailure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
        return false;
    }
    final result = await sl<DeliveryReceiptRepository>().approveDeliveryReceipt(r.id, path);
    switch (result) {
      case AppSuccess():
        messenger.showSnackBar(const SnackBar(content: Text('تم اعتماد السند')));
        return true;
      case AppFailure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
        return false;
    }
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('تعذر اعتماد السند، حاول مرة أخرى')));
    return false;
  }
}

/// Confirms, then rejects a pending submission. True if it was rejected.
Future<bool> rejectReceipt(BuildContext context, DeliveryReceipt r) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.cancel_outlined, color: Theme.of(ctx).colorScheme.error),
      title: const Text('رفض السند؟'),
      content: Text('سيظهر للجهة (${r.submitterName ?? ''}) أن سندها مرفوض، ويُزال من قوائمك.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('رفض'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final result = await sl<DeliveryReceiptRepository>().rejectDeliveryReceipt(r.id);
  switch (result) {
    case AppSuccess():
      messenger.showSnackBar(const SnackBar(content: Text('تم رفض السند')));
      return true;
    case AppFailure(:final error):
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
  }
}

enum ReceiptAction { open, share, edit, delete, approve, reject }

/// ⋮ menu for a سند. Share and open need the PDF; edit/delete only the creator's.
class ReceiptMenuButton extends StatelessWidget {
  final DeliveryReceipt receipt;

  /// Called after a successful edit or delete, so the list can refresh.
  final VoidCallback onChanged;

  const ReceiptMenuButton({super.key, required this.receipt, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final manage = canManageReceipt(context, receipt);
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<ReceiptAction>(
      tooltip: 'خيارات السند',
      onSelected: (action) async {
        switch (action) {
          case ReceiptAction.open:
            await openReceiptPdf(context, receipt);
          case ReceiptAction.share:
            await shareReceiptPdf(context, receipt);
          case ReceiptAction.edit:
            if (await editReceipt(context, receipt)) onChanged();
          case ReceiptAction.delete:
            if (context.mounted && await deleteReceipt(context, receipt)) onChanged();
          case ReceiptAction.approve:
            if (await approveReceipt(context, receipt)) onChanged();
          case ReceiptAction.reject:
            if (await rejectReceipt(context, receipt)) onChanged();
        }
      },
      itemBuilder: (_) => [
        if (receipt.status == ReceiptStatus.pending) ...[
          const PopupMenuItem(
            value: ReceiptAction.approve,
            child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('اعتماد')),
          ),
          PopupMenuItem(
            value: ReceiptAction.reject,
            child: ListTile(
              leading: Icon(Icons.cancel_outlined, color: error),
              title: Text('رفض', style: TextStyle(color: error)),
            ),
          ),
        ],
        if (receipt.pdfUrl != null)
          const PopupMenuItem(
            value: ReceiptAction.open,
            child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('فتح السند')),
          ),
        if (receipt.pdfUrl != null)
          const PopupMenuItem(
            value: ReceiptAction.share,
            child: ListTile(leading: Icon(Icons.share_outlined), title: Text('مشاركة السند')),
          ),
        if (manage) ...[
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
