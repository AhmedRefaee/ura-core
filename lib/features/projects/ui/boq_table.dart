import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../logic/boq_excel.dart';

/// The quotation as a spreadsheet-style table: columns and order exactly as
/// the Excel export ([boqHeaders]), header row pinned on top, totals row
/// pinned at the bottom.
///
/// Built lazily in both directions (TableView), so only on-screen cells
/// exist -- a 300-line quotation costs the same as a 10-line one. It scrolls
/// itself, so it needs a bounded height from its parent.
class BoqTable extends StatefulWidget {
  final List<ProjectItem> items;

  /// Price columns are dropped for roles the server doesn't show pricing to.
  final bool showPrices;
  final ValueChanged<ProjectItem>? onTap;
  final ValueChanged<ProjectItem>? onLongPress;

  const BoqTable({
    super.key,
    required this.items,
    required this.showPrices,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<BoqTable> createState() => _BoqTableState();
}

class _BoqTableState extends State<BoqTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  List<ProjectItem> get items => widget.items;
  bool get showPrices => widget.showPrices;
  ValueChanged<ProjectItem>? get onTap => widget.onTap;
  ValueChanged<ProjectItem>? get onLongPress => widget.onLongPress;

  static const _rowHeight = 52.0;
  static const _headerHeight = 44.0;

  // Natural widths in boqHeaders order; scaled up to fill wide screens.
  static const _wide = [
    120.0,
    170.0,
    280.0,
    80.0,
    80.0,
    95.0,
    110.0,
    110.0,
    125.0,
  ];
  // On phones the first two columns stay pinned, so they get narrower.
  static const _narrowPinned = [84.0, 116.0];

  @override
  Widget build(BuildContext context) {
    final columns = showPrices ? boqHeaders.length : 5;
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final line = BorderSide(color: theme.dividerColor);
    final headerBg = theme.colorScheme.surfaceContainerHighest;
    final derivedBg = theme.colorScheme.surfaceContainerHigh.withValues(
      alpha: 0.5,
    );
    final bold = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final body = theme.textTheme.bodySmall;
    final totals = showPrices ? BoqTotals.of(items) : null;
    final hasTotalsRow = totals != null;
    final rowCount = 1 + items.length + (hasTotalsRow ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final natural = _wide.take(columns).fold<double>(0, (a, b) => a + b);
        final fits = constraints.maxWidth >= natural;
        final widths = [
          for (var c = 0; c < columns; c++)
            fits
                ? _wide[c] * constraints.maxWidth / natural
                : (c < 2 ? _narrowPinned[c] : _wide[c]),
        ];

        // Visible, draggable scrollbars on both axes: a mouse can't swipe.
        return Scrollbar(
          controller: _vertical,
          thumbVisibility: true,
          interactive: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: !fits,
            interactive: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: TableView.builder(
              verticalDetails: ScrollableDetails.vertical(
                controller: _vertical,
              ),
              // Column 0 sits on the right in RTL, like the Excel sheet.
              horizontalDetails: ScrollableDetails.horizontal(
                controller: _horizontal,
                reverse: rtl,
              ),
              pinnedRowCount: 1,
              trailingPinnedRowCount: hasTotalsRow ? 1 : 0,
              pinnedColumnCount: fits ? 0 : 2,
              columnCount: columns,
              rowCount: rowCount,
              columnBuilder: (c) => TableSpan(
                extent: FixedTableSpanExtent(widths[c]),
                backgroundDecoration: c >= 6
                    ? TableSpanDecoration(color: derivedBg)
                    : null,
                foregroundDecoration: TableSpanDecoration(
                  border: TableSpanBorder(trailing: line),
                ),
              ),
              rowBuilder: (r) {
                final isHeader = r == 0;
                final isTotals = hasTotalsRow && r == rowCount - 1;
                final item = isHeader || isTotals ? null : items[r - 1];
                return TableSpan(
                  extent: FixedTableSpanExtent(
                    isHeader ? _headerHeight : _rowHeight,
                  ),
                  backgroundDecoration: isHeader || isTotals
                      ? TableSpanDecoration(color: headerBg)
                      : null,
                  foregroundDecoration: TableSpanDecoration(
                    border: TableSpanBorder(trailing: line),
                  ),
                  cursor: item != null && onTap != null
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  recognizerFactories: item == null
                      ? const {}
                      : {
                          if (onTap != null)
                            TapGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  TapGestureRecognizer
                                >(
                                  TapGestureRecognizer.new,
                                  (t) => t.onTap = () => onTap!(item),
                                ),
                          if (onLongPress != null)
                            LongPressGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  LongPressGestureRecognizer
                                >(
                                  LongPressGestureRecognizer.new,
                                  (t) =>
                                      t.onLongPress = () => onLongPress!(item),
                                ),
                        },
                );
              },
              cellBuilder: (context, v) {
                final r = v.row, c = v.column;
                if (r == 0) {
                  return _cell(boqHeaders[c], bold, center: true, lines: 2);
                }
                if (hasTotalsRow && r == rowCount - 1) {
                  final text = switch (c) {
                    0 => 'الإجمالي (${items.length})',
                    7 => formatMoney(totals.subtotal),
                    8 => formatMoney(totals.total),
                    _ => '',
                  };
                  return _cell(text, bold, center: c != 0);
                }
                final item = items[r - 1];
                return switch (c) {
                  0 => _cell(item.category, body),
                  1 => _cell(item.itemName, body),
                  2 => _cell(item.description ?? '', body),
                  3 => _cell(formatQty(item.quantity), body, center: true),
                  4 => _cell(item.unit, body, center: true),
                  5 => _cell(_money(item.unitPrice), body, center: true),
                  6 => _cell(
                    _money(_withVat(item.unitPrice)),
                    body,
                    center: true,
                  ),
                  7 => _cell(_money(item.totalPrice), body, center: true),
                  _ => _cell(
                    _money(_withVat(item.totalPrice)),
                    body,
                    center: true,
                  ),
                };
              },
            ),
          ),
        );
      },
    );
  }

  static TableViewCell _cell(
    String text,
    TextStyle? style, {
    bool center = false,
    int lines = 2,
  }) => TableViewCell(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: center ? Alignment.center : AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: style,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
        ),
      ),
    ),
  );

  static String _money(double? v) => v == null ? '' : formatMoney(v);
  static double? _withVat(double? v) =>
      v == null ? null : ((v * (1 + kVatRate)) * 100).round() / 100;
}
