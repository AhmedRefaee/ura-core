import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../core/logging/app_logger.dart';
import '../../../core/storage/signed_storage_url.dart';
import 'delivery_receipt_pdf.dart';

/// One line of a سند being (re)printed from stored data.
class StoredReceiptLine {
  final String itemName;
  final String? contractDescription;
  final String unit;
  final double quantity;
  final String? note;
  const StoredReceiptLine({
    required this.itemName,
    this.contractDescription,
    required this.unit,
    required this.quantity,
    this.note,
  });
}

/// A missing or unreachable letterhead shouldn't block the سند -- the PDF just
/// goes out without a header image.
Future<Uint8List?> fetchLetterheadBytes(String? stored) async {
  final url = await SignedStorageUrl.resolve('project-letterheads', stored);
  if (url == null) return null;
  try {
    final res = await http.get(Uri.parse(url));
    return res.statusCode == 200 ? res.bodyBytes : null;
  } catch (e) {
    logger.w('receipt_pdf_builder → letterhead fetch failed: $e');
    return null;
  }
}

/// Rebuilds a filed سند's PDF from what was stored with it, the way
/// CreateDeliveryReceiptCubit built it the first time. [dateMode] is one of
/// ReceiptDateMode's names (today / blank / custom); "today" means the day it
/// was filed, not the day it is reprinted.
Future<Uint8List> buildStoredReceiptPdf({
  required String entityName,
  required String projectName,
  required String? letterheadStored,
  required String dateMode,
  required DateTime filedAt,
  DateTime? customDate,
  required bool fullDescription,
  String? categoryTitle,
  String? notes,
  required List<StoredReceiptLine> lines,
}) async {
  return DeliveryReceiptPdf.build(
    entityName: entityName,
    projectName: projectName,
    categoryTitle: categoryTitle,
    date: switch (dateMode) {
      'blank' => null,
      'custom' => customDate ?? filedAt.toLocal(),
      _ => filedAt.toLocal(),
    },
    clientLogoBytes: await fetchLetterheadBytes(letterheadStored),
    notes: notes,
    fullDescription: fullDescription,
    lines: [
      for (final l in lines)
        ReceiptPdfLine(
          itemName: l.itemName,
          description: fullDescription ? l.contractDescription : packagingOf(l.contractDescription),
          unit: l.unit,
          quantity: l.quantity,
          note: l.note,
        ),
    ],
  );
}
