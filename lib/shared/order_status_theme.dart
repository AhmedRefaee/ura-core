import 'package:flutter/material.dart';
import '../core/design_system/theme/colors/order_status_colors.dart';
import 'models/order.dart';

/// Traffic-light color scheme for order status.
/// RED = assigned, ORANGE = picked up, YELLOW = in-transit, GREEN = delivered.
extension OrderStatusTheme on OrderStatus {
  Color get color => switch (this) {
    OrderStatus.assigned => OrderStatusColors.assigned,
    OrderStatus.pickedUp => OrderStatusColors.pickedUp,
    OrderStatus.onTheMove => OrderStatusColors.onTheMove,
    OrderStatus.delivered => OrderStatusColors.delivered,
    OrderStatus.deliveredToStorage => OrderStatusColors.deliveredToStorage,
  };

  IconData get icon => switch (this) {
    OrderStatus.assigned => Icons.assignment_outlined,
    OrderStatus.pickedUp => Icons.inventory_2_outlined,
    OrderStatus.onTheMove => Icons.local_shipping_outlined,
    OrderStatus.delivered => Icons.check_circle_outline,
    OrderStatus.deliveredToStorage => Icons.storage_outlined,
  };
}
