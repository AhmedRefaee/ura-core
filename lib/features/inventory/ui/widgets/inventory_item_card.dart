import 'package:flutter/material.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/inventory_item.dart';
import 'availability_badge.dart';

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
    return Card(
      margin: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalMedium, vertical: AppSpacing.verticalSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        child: Padding(
          padding: AppSpacing.allMedium,
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 32, color: AppColors.textSecondary),
              SizedBox(width: AppSpacing.horizontalMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${item.quantity} ${item.unit}',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        if (item.sku != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            'SKU: ${item.sku}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                    if (item.category != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.category!,
                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AvailabilityBadge(status: item.availabilityStatus),
            ],
          ),
        ),
      ),
    );
  }
}
