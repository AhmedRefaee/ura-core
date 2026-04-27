import 'package:flutter/material.dart';
import '../../../../shared/models/order.dart';
import '../../../../shared/widgets/order_list_tile.dart';

class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  const OrderCard({super.key, required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    return OrderListTile(order: order, onTap: onTap);
  }
}
