import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle, Uint8List;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../shared/utils/quantity_format.dart';
import 'pdf_rtl_text.dart';

class ReceiptPdfLine {
  final String itemName;
  final String? description;
  final String unit;
  final double quantity;
  final String? note;
  const ReceiptPdfLine({
    required this.itemName,
    this.description,
    required this.unit,
    required this.quantity,
    this.note,
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

  // Each items table is its own top-level widget in MultiPage's build list,
  // not one Table spanning everything -- pw.Table only auto-splits across
  // pages when MultiPage sees it directly (`child is SpanningWidget`), but
  // this file wraps every table in _ltr (a plain Directionality), which
  // hides that from the check. Chunking sidesteps it entirely: a page
  // simply starts a fresh top-level widget wherever the previous one ran
  // out of room, which is exactly the page-break behavior we want anyway,
  // each chunk small enough (<=20 rows) to always fit on one page by
  // itself. Row numbers (م) count across chunks, never resetting per page.
  static const _maxRowsPerPage = 20;

  static Future<Uint8List> build({
    required String entityName,
    // Null leaves the المشروع line off entirely -- the سند names only the
    // entity (the settings dialog's إخفاء اسم المشروع).
    String? projectName,
    // Null when the rep/verifier chose to leave the date for the receiving
    // side to fill in by hand at the moment of delivery, rather than
    // stamping it with whatever day the سند happened to be filed/printed.
    DateTime? date,
    required List<ReceiptPdfLine> lines,
    Uint8List? clientLogoBytes,
    String? notes,
    // Lines carry whole contract descriptions -- rows grow to fit them, so
    // the fixed-height 20-rows-per-page chunking below can't apply.
    bool fullDescription = false,
    // Set when the سند was split per category: printed as a heading right
    // above the items so each سند says which category it covers.
    String? categoryTitle,
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

    // Every piece of data text goes through here once, so its brackets face
    // the right way and Latin reads forwards -- see fixRtlTextForPdf. The
    // labels below are fixed text with neither.
    final baseFont = theme.defaultTextStyle.font;
    final glyphs = baseFont is pw.TtfFont ? TtfParser(baseFont.data).charToGlyphIndexMap : null;
    String fix(String s) => glyphs == null ? s : fixRtlTextForPdf(s, glyphs.containsKey);
    entityName = fix(entityName);
    if (projectName != null) projectName = fix(projectName);
    if (notes != null) notes = fix(notes);
    if (categoryTitle != null) categoryTitle = fix(categoryTitle);
    lines = [
      for (final l in lines)
        ReceiptPdfLine(
          itemName: fix(l.itemName),
          description: l.description == null ? null : fix(l.description!),
          unit: fix(l.unit),
          quantity: l.quantity,
          note: l.note == null ? null : fix(l.note!),
        ),
    ];

    final dateText = date == null
        // Same day/month/year shape as a real date, blank segments -- not
        // dots -- for the receiving side to fill in by hand.
        ? '      /      /      '
        : '${date.day.toString().padLeft(2, '0')} / ${date.month.toString().padLeft(2, '0')} / ${date.year}';
    final category = categoryTitle?.trim() ?? '';
    pw.Widget categoryHeading() => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _t('الفئة : $category', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        // Pages after the first are only items; they repeat the date (and
        // the category, on a split سند) so a loose page still says which
        // سند it belongs to.
        header: (ctx) => ctx.pageNumber == 1
            ? _header(uraLogo, clientLogoBytes)
            : pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _header(uraLogo, clientLogoBytes),
                  _infoLine('التاريخ', dateText),
                  pw.SizedBox(height: 4),
                  if (category.isNotEmpty) categoryHeading(),
                ],
              ),
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
          if (projectName != null) _infoLine('المشروع', projectName),
          _infoLine('التاريخ', dateText),
          pw.SizedBox(height: 6),
          if (category.isNotEmpty) categoryHeading(),
          // Rows of unknown height can't be chunked by count. One table,
          // handed to MultiPage directly (pw.Table ignores text direction,
          // so it needs no _ltr wrapper), splits across pages by itself.
          if (fullDescription)
            _itemsTable(lines, 0, wrap: true)
          else
          for (var start = 0; start < lines.length; start += _maxRowsPerPage) ...[
            // A hard break before every chunk but the first: two chunks
            // both fitting in the leftover space on one page would still
            // read as "more than 20 rows on this page" even though each
            // table on it is individually capped -- one table per page.
            if (start > 0) pw.NewPage(),
            _itemsTable(
              lines.sublist(start, (start + _maxRowsPerPage).clamp(0, lines.length)),
              start,
            ),
          ],
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
  static pw.Widget _t(String text, {pw.TextStyle? style, pw.TextAlign align = pw.TextAlign.right, int? maxLines}) =>
      pw.Text(text,
          style: style,
          textAlign: align,
          textDirection: pw.TextDirection.rtl,
          maxLines: maxLines,
          overflow: maxLines != null ? pw.TextOverflow.clip : pw.TextOverflow.visible);

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

  // maxLines: 1 for free-text cells (the ملاحظات column) -- the row's
  // height is fixed, so unlike the item name (a curated catalog string,
  // reliably short) a user-typed note has to be bounded or it would spill
  // past the row instead of wrapping into it.
  // [wrap]: the row grows with its text (min the fixed height) instead.
  static pw.Widget _cell(String text,
          {bool header = false, pw.TextAlign align = pw.TextAlign.center, bool singleLine = false, bool wrap = false}) =>
      pw.Container(
        height: wrap ? null : (header ? 20 : 22),
        constraints: wrap ? pw.BoxConstraints(minHeight: header ? 20 : 22) : null,
        padding: wrap
            ? const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3)
            : const pw.EdgeInsets.symmetric(horizontal: 4),
        alignment: align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.center,
        color: header ? PdfColors.grey400 : null,
        child: _t(text,
            align: align,
            maxLines: singleLine ? 1 : null,
            style: header
                ? pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)
                : const pw.TextStyle(fontSize: 9.5)),
      );

  /// One page's worth of rows (<=_maxRowsPerPage). [startIndex] is this
  /// chunk's offset into the full line list, so م keeps counting up across
  /// pages instead of restarting at 1 on each one.
  /// [wrap]: rows grow to fit full descriptions, and the table is returned
  /// bare so MultiPage can split it across pages.
  static pw.Widget _itemsTable(List<ReceiptPdfLine> chunk, int startIndex, {bool wrap = false}) {
    // Visual left-to-right: ملاحظات | الكمية | الوحدة | اسم الصنف ووصفه | م
    final table = pw.Table(
      // Only matters when [wrap] lets one cell outgrow the others.
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      border: const pw.TableBorder(
        left: _border, right: _border, top: _border, bottom: _border,
        horizontalInside: _border, verticalInside: _border,
      ),
      // Full descriptions take some of ملاحظات' width -- notes stay one line.
      columnWidths: {
        0: pw.FlexColumnWidth(wrap ? 1.5 : 2.3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(wrap ? 4.4 : 3.6),
        4: const pw.FixedColumnWidth(34),
      },
      children: [
        pw.TableRow(children: [
          _cell('ملاحظات', header: true),
          _cell('الكمية', header: true),
          _cell('الوحدة', header: true),
          _cell('اسم الصنف ووصفه', header: true),
          _cell('م', header: true),
        ]),
        for (var i = 0; i < chunk.length; i++)
          pw.TableRow(children: [
            _cell(chunk[i].note ?? '', singleLine: true, wrap: wrap),
            _cell(formatQty(chunk[i].quantity), wrap: wrap),
            _cell(chunk[i].unit, wrap: wrap),
            _cell(
              [chunk[i].itemName, if (chunk[i].description?.trim().isNotEmpty ?? false) chunk[i].description!.trim()]
                  .join(' - '),
              align: pw.TextAlign.right,
              wrap: wrap,
            ),
            _cell('${startIndex + i + 1}', wrap: wrap),
          ]),
      ],
    );
    return wrap ? table : _ltr(table);
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
