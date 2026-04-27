import 'package:flutter/material.dart';
import 'models/order.dart';

/// Traffic-light color scheme for order status.
/// RED = pre-movement, AMBER = in-transit, GREEN = delivered.
extension OrderStatusTheme on OrderStatus {
  Color get color => switch (this) {
        OrderStatus.assigned || OrderStatus.pickedUp => Colors.red,
        OrderStatus.onTheMove => Colors.amber.shade700,
        OrderStatus.delivered || OrderStatus.deliveredToStorage => Colors.green,
      };

  IconData get icon => switch (this) {
        OrderStatus.assigned => Icons.assignment_outlined,
        OrderStatus.pickedUp => Icons.inventory_2_outlined,
        OrderStatus.onTheMove => Icons.local_shipping_outlined,
        OrderStatus.delivered => Icons.check_circle_outline,
        OrderStatus.deliveredToStorage => Icons.storage_outlined,
      };
}
