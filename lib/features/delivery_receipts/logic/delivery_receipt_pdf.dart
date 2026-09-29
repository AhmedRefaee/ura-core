import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle, Uint8List;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../shared/utils/quantity_format.dart';

class ReceiptPdfLine {
  final String itemName;
  final String? description;
  final String unit;
  final double quantity;
  const ReceiptPdfLine({
    required this.itemName,
    this.description,
    required this.unit,
    required this.quantity,
  });
}

/// The packaging part of a quotation description, for the سند.
///
/// Descriptions are long specs that end with the packaging after the last
/// "/" ("…جودة عالية / كرتون 4*2.75كيلو جرام", "…بروتين لا يقل عن 6 ملغم/
/// 180مل"). Returns that tail; a short description without "/" as-is;
/// otherwise null -- the سند shows just the item name rather than a spec
/// paragraph.
String? packagingOf(String? description) {
  final d = description?.trim() ?? '';
  if (d.isEmpty) return null;
  final slash = d.lastIndexOf('/');
  if (slash >= 0) {
    final tail = d.substring(slash + 1).trim();
    if (tail.isNotEmpty && tail.length <= 40) return tail;
  }
  return d.length <= 30 ? d : null;
}

/// Builds the سند استلام بضاعة PDF, laid out after the company's paper form:
/// URA's logo always on the left, the receiving side's logo on the right.
/// No pricing on purpose -- this is a logistics document, not the quotation.
class DeliveryReceiptPdf {
  static const _uraGreen = PdfColor.fromInt(0xFF5B9A3C);
  static const _border = pw.BorderSide(width: 0.8);

  static Future<Uint8List> build({
    required String entityName,
    required String projectName,
    required DateTime date,
    required List<ReceiptPdfLine> lines,
    Uint8List? clientLogoBytes,
    String? notes,
    @visibleForTesting pw.ThemeData? theme,
  }) async {
    // The PDF's built-in fonts have no Arabic glyphs. Noto Sans Arabic, not
    // Cairo: with the pdf package's shaper Cairo (and Tajawal) mangle a final
    // yaa after a non-joining letter -- "لنادي" printed as "لناه", "زبادي"
    // as "زباج". Noto Sans Arabic has no "*" or "/", hence the Latin
    // fallback for packaging like "كرتون 4*2.75". Fetched once and cached by
    // `printing`; works on mobile and web.
    theme ??= pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansArabicRegular(),
      bold: await PdfGoogleFonts.notoSansArabicBold(),
      fontFallback: [
        await PdfGoogleFonts.notoSansRegular(),
        await PdfGoogleFonts.notoSansBold(),
      ],
    );
    final uraLogo = (await rootBundle.load('assets/branding/ura_logo.png')).buffer.asUint8List();

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        header: (_) => _header(uraLogo, clientLogoBytes),
        footer: (ctx) => ctx.pagesCount < 2
            ? pw.SizedBox()
            : pw.Center(
                child: _t('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ),
        build: (_) => [
          // A bottom border, not TextDecoration.underline: the underline lands
          // offset under shaped RTL text.
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))),
              child: _t('سند استلام بضاعة',
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          pw.SizedBox(height: 10),
          _infoLine('الجهة المستفيدة', entityName),
          _infoLine('المشروع', projectName),
          _infoLine('التاريخ',
              '${date.day.toString().padLeft(2, '0')} / ${date.month.toString().padLeft(2, '0')} / ${date.year}'),
          pw.SizedBox(height: 6),
          _itemsTable(lines),
          if (notes != null && notes.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: _t('ملاحظات: ${notes.trim()}', style: const pw.TextStyle(fontSize: 10)),
              ),
            ),
          pw.SizedBox(height: 10),
          _signatures(),
        ],
      ),
    );
    return doc.save();
  }

  /// Every Text in here sets rtl itself: the rows/table below are laid out in
  /// an explicit LTR frame so column order is fixed visually, and Arabic only
  /// shapes correctly when the Text itself is rtl.
  static pw.Widget _t(String text, {pw.TextStyle? style, pw.TextAlign align = pw.TextAlign.right}) =>
      pw.Text(text, style: style, textAlign: align, textDirection: pw.TextDirection.rtl);

  static pw.Widget _ltr(pw.Widget child) =>
      pw.Directionality(textDirection: pw.TextDirection.ltr, child: child);

  static pw.Widget _header(Uint8List uraLogo, Uint8List? clientLogo) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: _ltr(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(pw.MemoryImage(uraLogo), height: 42),
                _t('شركة روح النمو المتحدة',
                    align: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _uraGreen)),
                pw.Text('United Rouh AlNomu',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _uraGreen)),
              ],
            ),
            pw.Spacer(),
            if (clientLogo != null)
              pw.SizedBox(
                height: 70,
                width: 170,
                child: pw.Image(pw.MemoryImage(clientLogo), fit: pw.BoxFit.contain),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _infoLine(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _t('$label : $value', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        ),
      );

  static pw.Widget _cell(String text, {bool header = false, pw.TextAlign align = pw.TextAlign.center}) =>
      pw.Container(
        height: header ? 20 : 22,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
        alignment: align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.center,
        color: header ? PdfColors.grey400 : null,
        child: _t(text,
            align: align,
            style: header
                ? pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)
                : const pw.TextStyle(fontSize: 9.5)),
      );

  static pw.Widget _itemsTable(List<ReceiptPdfLine> lines) {
    // Visual left-to-right: ملاحظات | الكمية | الوحدة | اسم الصنف ووصفه | م
    return _ltr(
      pw.Table(
        border: const pw.TableBorder(
          left: _border, right: _border, top: _border, bottom: _border,
          horizontalInside: _border, verticalInside: _border,
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.3),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(3.6),
          4: pw.FixedColumnWidth(34),
        },
        children: [
          pw.TableRow(children: [
            _cell('ملاحظات', header: true),
            _cell('الكمية', header: true),
            _cell('الوحدة', header: true),
            _cell('اسم الصنف ووصفه', header: true),
            _cell('م', header: true),
          ]),
          for (var i = 0; i < lines.length; i++)
            pw.TableRow(children: [
              _cell(''),
              _cell(formatQty(lines[i].quantity)),
              _cell(lines[i].unit),
              _cell(
                [lines[i].itemName, if (lines[i].description?.trim().isNotEmpty ?? false) lines[i].description!.trim()]
                    .join(' - '),
                align: pw.TextAlign.right,
              ),
              _cell('${i + 1}'),
            ]),
        ],
      ),
    );
  }

  /// Both blocks are left blank for a handwritten name and signature at the
  /// moment of delivery -- the person signing isn't necessarily the rep who
  /// filed the سند in the app, so pre-filling a name here would be wrong.
  static pw.Widget _signatures() {
    pw.Widget block(String title) => pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _t(title, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                _t('الاسم /', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 14),
                _t('التوقيع /', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
              ],
            ),
          ),
        );

    return _ltr(
      pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            block('مندوب الشركة'),
            block('مسئول الموقع'),
          ],
        ),
      ),
    );
  }
}
