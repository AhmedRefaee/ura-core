import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ura_core/features/delivery_receipts/logic/delivery_receipt_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a سند with our logo and the chosen lines', () async {
    // Tests can't reach Google Fonts; any local Arabic-capable TTF will do.
    final font = File('C:/Windows/Fonts/tahoma.ttf');
    final bold = File('C:/Windows/Fonts/tahomabd.ttf');
    if (!font.existsSync()) return;

    final bytes = await DeliveryReceiptPdf.build(
      entityName: 'صندوق التنمية العقارية',
      projectName: 'توريد أثاث المقر الرئيسي',
      repName: 'أحمد رفاعي',
      date: DateTime(2026, 9, 26),
      notes: 'تم التسليم في الموقع',
      clientLogoBytes: Platform.environment['RECEIPT_CLIENT_LOGO'] == null
          ? null
          : File(Platform.environment['RECEIPT_CLIENT_LOGO']!).readAsBytesSync(),
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(font.readAsBytesSync().buffer.asByteData()),
        bold: pw.Font.ttf((bold.existsSync() ? bold : font).readAsBytesSync().buffer.asByteData()),
      ),
      lines: const [
        ReceiptPdfLine(itemName: 'كرسي مكتب', description: 'جلد أسود بعجلات', unit: 'حبة', quantity: 12),
        ReceiptPdfLine(itemName: 'طاولة اجتماعات', unit: 'حبة', quantity: 2),
        ReceiptPdfLine(itemName: 'ورق تصوير A4', unit: 'كرتون', quantity: 7.5),
      ],
    );

    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['RECEIPT_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
