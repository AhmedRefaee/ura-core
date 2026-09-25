import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../shared/utils/quantity_format.dart';

class ReceiptPdfLine {
  final String itemName;
  final String unit;
  final double quantity;
  const ReceiptPdfLine({required this.itemName, required this.unit, required this.quantity});
}

/// Builds the سند استلام PDF. No pricing on purpose -- this is a logistics
/// document, not the quotation.
class DeliveryReceiptPdf {
  static Future<Uint8List> build({
    required String entityName,
    required String projectName,
    required String repName,
    required DateTime date,
    required List<ReceiptPdfLine> lines,
    Uint8List? letterheadBytes,
    String? notes,
  }) async {
    // The PDF's built-in fonts have no Arabic glyphs; Cairo is fetched once
    // and cached by `printing`, and works on both mobile and web.
    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.cairoRegular(),
      bold: await PdfGoogleFonts.cairoBold(),
    );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => letterheadBytes == null
            ? pw.SizedBox()
            : pw.Container(
                height: 90,
                margin: const pw.EdgeInsets.only(bottom: 12),
                alignment: pw.Alignment.center,
                child: pw.Image(pw.MemoryImage(letterheadBytes), fit: pw.BoxFit.contain),
              ),
        footer: (ctx) => pw.Column(children: [
          pw.SizedBox(height: 36),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _signature('توقيع المستلم'),
              _signature('توقيع المندوب'),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ]),
        build: (_) => [
          pw.Center(
            child: pw.Text('سند استلام',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 16),
          _meta('الجهة', entityName),
          _meta('المشروع', projectName),
          _meta('المندوب', repName),
          _meta('التاريخ',
              '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['م', 'البند', 'الوحدة', 'الكمية'],
            data: [
              for (var i = 0; i < lines.length; i++)
                ['${i + 1}', lines[i].itemName, lines[i].unit, formatQty(lines[i].quantity)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.center,
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1.5),
            },
          ),
          if (notes != null && notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('ملاحظات: ${notes.trim()}'),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _meta(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(children: [
          pw.Text('$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(value),
        ]),
      );

  static pw.Widget _signature(String label) => pw.Column(children: [
        pw.Container(width: 150, height: 1, color: PdfColors.grey700),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      ]);
}
