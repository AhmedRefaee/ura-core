import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/profile.dart';

/// Generates a سند استلام (delivery receipt) PDF document.
/// Pure function — no I/O, just PDF generation.
class DeliveryReceiptPdf {
  static Future<pw.Document> generate({
    required DeliveryReceipt receipt,
    required Entity entity,
    required Project project,
    required Profile rep,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Letterhead (if available)
              if (receipt.letterheadImageUrl != null)
                pw.Container(
                  height: 80,
                  margin: pw.EdgeInsets.only(bottom: 20),
                  child: pw.Image(
                    pw.MemoryImage(
                      // Note: In real usage, you'd fetch the image bytes from the URL
                      // This is a placeholder showing the structure
                      Future.value([] as List<int>).then((_) => [] as List<int>) as Future<List<int>>,
                    ),
                    fit: pw.BoxFit.contain,
                  ),
                )
              else
                pw.SizedBox(height: 20),

              // Header
              pw.Center(
                child: pw.Text(
                  'سند استلام',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              // Receipt metadata
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('المشروع: ${project.name}', style: pw.TextStyle(fontSize: 12)),
                      pw.Text('الجهة: ${entity.name}', style: pw.TextStyle(fontSize: 12)),
                      pw.Text('المندوب: ${rep.fullName}', style: pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'التاريخ: ${_formatDate(receipt.deliveredAt)}',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        'الرقم: ${receipt.id.substring(0, 8)}',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Items table
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(8),
                        child: pw.Text('البند', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(8),
                        child: pw.Text('الوحدة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(8),
                        child: pw.Text('الكمية', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  // Item rows
                  ...receipt.items.map((item) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: pw.EdgeInsets.all(8),
                          child: pw.Text(item.itemNameSnapshot, style: pw.TextStyle(fontSize: 11)),
                        ),
                        pw.Padding(
                          padding: pw.EdgeInsets.all(8),
                          child: pw.Text(item.unitSnapshot, style: pw.TextStyle(fontSize: 11)),
                        ),
                        pw.Padding(
                          padding: pw.EdgeInsets.all(8),
                          child: pw.Text(item.quantityDelivered.toString(), style: pw.TextStyle(fontSize: 11)),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),

              // Notes (if any)
              if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
                pw.Text(
                  'ملاحظات:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                ),
                pw.Text(
                  receipt.notes!,
                  style: pw.TextStyle(fontSize: 11),
                ),
              ],

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Text(
                'تم إنشاء هذا السند رقميًا بواسطة نظام URA',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
