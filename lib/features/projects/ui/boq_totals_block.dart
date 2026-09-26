import 'package:flutter/material.dart';
import '../../../shared/utils/quantity_format.dart';
import '../logic/boq_excel.dart';

class BoqTotalsBlock extends StatelessWidget {
  final BoqTotals totals;
  final bool grand;
  const BoqTotalsBlock({super.key, required this.totals, this.grand = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = grand ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium;
    Widget line(String label, double value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? style?.copyWith(fontWeight: FontWeight.bold) : style)),
            Text(formatMoney(value), style: bold ? style?.copyWith(fontWeight: FontWeight.bold) : style),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: grand ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
      child: Column(children: [
        if (grand) line('إجمالي العرض', totals.subtotal, bold: true) else line('الإجمالي غير شامل الضريبة', totals.subtotal),
        line('ضريبة القيمة المضافة ${(kVatRate * 100).round()}%', totals.vat),
        line(grand ? 'إجمالي العرض شامل الضريبة' : 'الإجمالي شامل الضريبة', totals.total, bold: true),
      ]),
    );
  }
}
