import 'package:flutter/material.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../logic/boq_excel.dart';

/// The quotation as a table, columns and order exactly as the Excel export
/// ([boqHeaders]), with a totals row at the bottom.
///
/// Fills the width when there is room; otherwise it scrolls sideways under
/// an always-visible, draggable scrollbar -- a mouse can't swipe, so a
/// hidden-scrollbar strip would strand the columns past the edge on web.
class BoqTable extends StatefulWidget {
  final List<ProjectItem> items;

  /// Price columns are dropped for roles the server doesn't show pricing to.
  final bool showPrices;
  final ValueChanged<ProjectItem>? onTap;
  final ValueChanged<ProjectItem>? onLongPress;

  const BoqTable({super.key, required this.items, required this.showPrices, this.onTap, this.onLongPress});

  @override
  State<BoqTable> createState() => _BoqTableState();
}

class _BoqTableState extends State<BoqTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Natural widths, in boqHeaders order. Used as-is when scrolling and as
  // flex weights when the table fills the available width.
  static const _widths = [120.0, 170.0, 280.0, 80.0, 80.0, 95.0, 110.0, 110.0, 125.0];

  @override
  Widget build(BuildContext context) {
    final columns = widget.showPrices ? boqHeaders.length : 5;
    final natural = _widths.take(columns).fold<double>(0, (a, b) => a + b);

    return LayoutBuilder(builder: (context, constraints) {
      final fits = constraints.maxWidth >= natural;
      final table = _table(context, columns, fits);
      if (fits) return table;
      return Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 14),
          child: SizedBox(width: natural, child: table),
        ),
      );
    });
  }

  Widget _table(BuildContext context, int columns, bool flex) {
    final theme = Theme.of(context);
    final border = BorderSide(color: theme.dividerColor);
    final headerBg = theme.colorScheme.surfaceContainerHighest;
    final derivedBg = theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5);
    final bold = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold);
    final body = theme.textTheme.bodySmall;

    Widget cell(String text, {TextStyle? style, bool start = false, Color? color}) => Container(
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          alignment: start ? AlignmentDirectional.centerStart : Alignment.center,
          child: Text(text, style: style ?? body, textAlign: start ? TextAlign.start : TextAlign.center),
        );

    Widget tappable(ProjectItem item, Widget child) => widget.onTap == null && widget.onLongPress == null
        ? child
        : TableRowInkWell(
            onTap: widget.onTap == null ? null : () => widget.onTap!(item),
            onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(item),
            child: child,
          );

    String money(double? v) => v == null ? '' : formatMoney(v);
    double? withVat(double? v) => v == null ? null : ((v * (1 + kVatRate)) * 100).round() / 100;
    final totals = BoqTotals.of(widget.items);

    return Table(
      border: TableBorder(
        top: border,
        bottom: border,
        left: border,
        right: border,
        horizontalInside: border,
        verticalInside: border,
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
      columnWidths: {
        for (var c = 0; c < columns; c++)
          c: flex ? FlexColumnWidth(_widths[c]) : FixedColumnWidth(_widths[c]),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerBg),
          children: [for (var c = 0; c < columns; c++) cell(boqHeaders[c], style: bold)],
        ),
        for (final item in widget.items)
          TableRow(children: [
            tappable(item, cell(item.category, start: true)),
            tappable(item, cell(item.itemName, start: true)),
            tappable(item, cell(item.description ?? '', start: true)),
            tappable(item, cell(formatQty(item.quantity))),
            tappable(item, cell(item.unit)),
            if (widget.showPrices) ...[
              tappable(item, cell(money(item.unitPrice))),
              tappable(item, cell(money(withVat(item.unitPrice)), color: derivedBg)),
              tappable(item, cell(money(item.totalPrice), color: derivedBg)),
              tappable(item, cell(money(withVat(item.totalPrice)), color: derivedBg)),
            ],
          ]),
        if (widget.showPrices)
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: [
              cell('الإجمالي (${widget.items.length} بند)', style: bold, start: true),
              for (var c = 1; c < 7; c++) cell(''),
              cell(formatMoney(totals.subtotal), style: bold),
              cell(formatMoney(totals.total), style: bold),
            ],
          ),
      ],
    );
  }
}
