import 'package:flutter/material.dart';

/// Order status colors following a fluid traffic-light progression.
/// RED = assigned, ORANGE = picked up, YELLOW = in-transit, GREEN = delivered.
/// Matches the current implementation in order_status_theme.dart.
class OrderStatusColors {
  const OrderStatusColors._();

  // ========================================
  // Order Status Colors (Traffic Light)
  // ========================================
  static const Color assigned = Color(0xFFE53935); // Red
  static const Color pickedUp = Color(0xFFFB8C00); // Orange
  static const Color onTheMove = Color(0xFFFBC02D); // Yellow
  static const Color delivered = Color(0xFF43A047); // Green
  static const Color deliveredToStorage = Color(0xFF43A047); // Green

  // ========================================
  // Order Direction Colors
  // ========================================
  static const Color orderDirectionOutbound = Color(0xFFFF9800); // Orange
  static const Color orderDirectionInboundRep = Color(0xFF009688); // Teal
  static const Color orderDirectionInboundExternal = Color(
    0xFF3F51B5,
  ); // Indigo
}
