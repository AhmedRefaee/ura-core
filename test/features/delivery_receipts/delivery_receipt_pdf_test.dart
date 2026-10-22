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
        ReceiptPdfLine(itemName: 'كرسي مكتب', description: 'جلد أسود بعجلات', unit: 'حبة', quantity: 12, note: 'يوجد خدش بسيط'),
        ReceiptPdfLine(itemName: 'طاولة اجتماعات', unit: 'حبة', quantity: 2),
        ReceiptPdfLine(itemName: 'ورق تصوير A4', unit: 'كرتون', quantity: 7.5),
      ],
    );

    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['RECEIPT_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('a null projectName builds -- the سند names only the entity', () async {
    final font = File('C:/Windows/Fonts/tahoma.ttf');
    if (!font.existsSync()) return;

    final bytes = await DeliveryReceiptPdf.build(
      entityName: 'صندوق التنمية العقارية',
      date: DateTime(2026, 9, 26),
      theme: pw.ThemeData.withFont(base: pw.Font.ttf(font.readAsBytesSync().buffer.asByteData())),
      lines: const [
        ReceiptPdfLine(itemName: 'كرسي مكتب', unit: 'حبة', quantity: 12),
      ],
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('a null date still builds -- the date line is left blank for handwriting', () async {
    final font = File('C:/Windows/Fonts/tahoma.ttf');
    final bold = File('C:/Windows/Fonts/tahomabd.ttf');
    if (!font.existsSync()) return;

    final bytes = await DeliveryReceiptPdf.build(
      entityName: 'صندوق التنمية العقارية',
      projectName: 'توريد أثاث المقر الرئيسي',
      date: null,
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(font.readAsBytesSync().buffer.asByteData()),
        bold: pw.Font.ttf((bold.existsSync() ? bold : font).readAsBytesSync().buffer.asByteData()),
      ),
      lines: const [
        ReceiptPdfLine(itemName: 'كرسي مكتب', unit: 'حبة', quantity: 12),
      ],
    );

    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['RECEIPT_PDF_BLANK_DATE_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('a split-by-category سند carries its category heading above the items', () async {
    final font = File('C:/Windows/Fonts/tahoma.ttf');
    final bold = File('C:/Windows/Fonts/tahomabd.ttf');
    if (!font.existsSync()) return;

    final bytes = await DeliveryReceiptPdf.build(
      entityName: 'صندوق التنمية العقارية',
      projectName: 'توريد مواد غذائية',
      date: DateTime(2026, 10, 22),
      categoryTitle: 'الحليب ومشتقاته',
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(font.readAsBytesSync().buffer.asByteData()),
        bold: pw.Font.ttf((bold.existsSync() ? bold : font).readAsBytesSync().buffer.asByteData()),
      ),
      lines: const [
        ReceiptPdfLine(itemName: 'لبنة', unit: 'كرتون', quantity: 5),
        ReceiptPdfLine(itemName: 'زبادي', unit: 'عبوة', quantity: 12),
      ],
    );

    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['RECEIPT_PDF_CATEGORY_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('more than 20 items spans multiple pages, numbered continuously; later pages repeat date and category',
      () async {
    final font = File('C:/Windows/Fonts/tahoma.ttf');
    final bold = File('C:/Windows/Fonts/tahomabd.ttf');
    if (!font.existsSync()) return;

    final bytes = await DeliveryReceiptPdf.build(
      entityName: 'صندوق التنمية العقارية',
      projectName: 'توريد أثاث المقر الرئيسي',
      date: DateTime(2026, 9, 26),
      categoryTitle: 'أثاث مكتبي',
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(font.readAsBytesSync().buffer.asByteData()),
        bold: pw.Font.ttf((bold.existsSync() ? bold : font).readAsBytesSync().buffer.asByteData()),
      ),
      lines: [
        for (var i = 1; i <= 25; i++)
          ReceiptPdfLine(itemName: 'بند $i', unit: 'حبة', quantity: i.toDouble()),
      ],
    );

    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['RECEIPT_PDF_MULTIPAGE_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('full contract descriptions grow their rows and still break across pages', () async {
    final font = File('C:/Windows/Fonts/tahoma.ttf');
    final bold = File('C:/Windows/Fonts/tahomabd.ttf');
    if (!font.existsSync()) return;

    // Long enough to wrap several lines -- 30 of them can't fit one page,
    // and a fixed-height row would clip them.
    const spec = 'جودة عالية مصنوعه من 100 % دسم الحليب الابقار، إنتاج حديث لا يتجاوز تاريخه '
        'شهراً من تاريخ التوريد، مطابق للمواصفات القياسية السعودية، معبأ في عبوات محكمة '
        'الإغلاق / كرتون 4*2.75كيلو جرام';
    final bytes = await DeliveryReceiptPdf.build(
      entityName: 'صندوق التنمية العقارية',
      projectName: 'توريد مواد غذائية',
      date: DateTime(2026, 10, 18),
      fullDescription: true,
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(font.readAsBytesSync().buffer.asByteData()),
        bold: pw.Font.ttf((bold.existsSync() ? bold : font).readAsBytesSync().buffer.asByteData()),
      ),
      lines: [
        for (var i = 1; i <= 30; i++)
          ReceiptPdfLine(itemName: 'لبنة $i', description: spec, unit: 'كرتون', quantity: i.toDouble()),
      ],
    );

    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['RECEIPT_PDF_FULL_DESC_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('the سند shows only the packaging part of a description', () {
    expect(packagingOf('جودة عالية مصنوعه من 100 % دسم الحليب الابقار / كرتون 4*2.75كيلو جرام'), 'كرتون 4*2.75كيلو جرام');
    expect(packagingOf('طازج مبرد من حليب الأبقار الطبيعي بروتين لا يقل عن 6 ملغم/ 180مل'), '180مل');
    expect(packagingOf('مصنوع من الحليب الطبيعي إنتاج جديد جودة عالية/ 16كيلو جرام'), '16كيلو جرام');
    expect(packagingOf('كرتون 20*240 جرام'), 'كرتون 20*240 جرام', reason: 'already short');
    expect(packagingOf('عصرة أولى عضوي طبيعي معصور على البارد نسبة حموضة لا تزيد عن 5% إنتاج جديد'), isNull);
    expect(packagingOf(null), isNull);
    expect(packagingOf('  '), isNull);
  });
}
