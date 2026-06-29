import 'package:flutter/material.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/utils/quantity_format.dart';
import 'availability_badge.dart';

Color _stockColor(AvailabilityStatus status) {
  switch (status) {
    case AvailabilityStatus.available:  return Colors.green;
    case AvailabilityStatus.low:        return Colors.orange;
    case AvailabilityStatus.outOfStock: return Colors.red;
  }
}

class InventoryItemCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback? onTap;
  final bool showActions;

  const InventoryItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.showActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockColor = _stockColor(item.availabilityStatus);
    final hasDescription =
        item.description != null && item.description!.trim().isNotEmpty;

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: AppSpacing.horizontalMedium,
        vertical: AppSpacing.verticalSmall,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name + badge ─────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.itemName,
                      style: AppTextStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AvailabilityBadge(status: item.availabilityStatus),
                ],
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 12),

              // ── Quantity  |  Unit — two clearly separated columns ─────────
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left column: the pure number
                    Expanded(
                      child: _InfoColumn(
                        label: 'الكمية المتوفرة',
                        value: formatQty(item.quantity),
                        valueStyle: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: stockColor,
                          height: 1.1,
                        ),
                        labelColor: scheme.onSurfaceVariant,
                      ),
                    ),

                    // Vertical separator
                    VerticalDivider(
                      width: 32,
                      color: scheme.outlineVariant,
                    ),

                    // Right column: the unit / packaging text
                    Expanded(
                      child: _InfoColumn(
                        label: 'الوحدة / التعبئة',
                        value: item.unit,
                        valueStyle: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                          height: 1.3,
                        ),
                        labelColor: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Description (size / volume / notes) ──────────────────────
              if (hasDescription) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 10),
                _LabeledRow(
                  label: 'الوصف',
                  value: item.description!.trim(),
                  scheme: scheme,
                ),
              ],

              // ── Secondary tags: category + SKU ───────────────────────────
              if (item.category != null || item.sku != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (item.category != null) ...[
                      _Tag(
                        label: item.category!,
                        background: scheme.secondaryContainer,
                        foreground: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (item.sku != null)
                      _Tag(
                        label: 'SKU: ${item.sku}',
                        background: scheme.surfaceContainerHighest,
                        foreground: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle valueStyle;
  final Color labelColor;

  const _InfoColumn({
    required this.label,
    required this.value,
    required this.valueStyle,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: labelColor,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _LabeledRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;

  const _LabeledRow({
    required this.label,
    required this.value,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
      ),
    );
  }
}
