import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/delivery_receipts/logic/pdf_rtl_text.dart';

/// What Noto Sans Arabic covers in ASCII: digits, space and ! , - . : --
/// no brackets, Latin letters, "*", "/" or "%".
bool notoArabicHas(int c) => c > 0x7E || c == 0x20 || c == 0x21 || (c >= 0x2C && c <= 0x3A && c != 0x2F);

String fix(String s) => fixRtlTextForPdf(s, notoArabicHas);

void main() {
  test('brackets in Arabic text are mirrored', () {
    expect(fix('مياه (40 عبوة)'), 'مياه )40 عبوة(');
    expect(fix('فلورايد (0.330) لتر'), 'فلورايد )0.330( لتر');
    expect(fix('سكر [مستورد]'), 'سكر ]مستورد[');
  });

  test('an unpaired bracket in Arabic text is mirrored too', () {
    expect(fix('قهوة (200 جم *12'), 'قهوة )200 جم *12');
  });

  test('a Latin word is reversed, its brackets following the Arabic around them', () {
    expect(fix('زبادي (UHV) طازج'), 'زبادي )VHU( طازج');
    expect(fix('120 PPM درجة'), '120 MPP درجة');
  });

  test('a Latin run keeps its own brackets and digits, reversed as units', () {
    expect(fix('مقاس XL (U10) و'), 'مقاس )10U( LX و');
    expect(fix('مشروب Cola 330ml بارد'), 'مشروب lm 330aloC بارد');
  });

  test('text with no brackets or Latin comes back unchanged', () {
    expect(fix('كرتون 4*2.75 / 1كيلو'), 'كرتون 4*2.75 / 1كيلو');
  });

  test('a font with brackets and Latin needs no help', () {
    expect(fixRtlTextForPdf('مياه (40 عبوة) UHV', (_) => true), 'مياه (40 عبوة) UHV');
  });
}
