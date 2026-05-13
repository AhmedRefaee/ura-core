import 'package:flutter/material.dart';

/// Order status colors following the traffic light pattern.
/// RED = pre-movement, AMBER = in-transit, GREEN = delivered.
/// Matches the current implementation in order_status_theme.dart.
class OrderStatusColors {
  const OrderStatusColors._();

  // ========================================
  // Order Status Colors (Traffic Light)
  // ========================================
  static const Color assigned = Color(0xFFE53935); // Red - pre-movement
  static const Color pickedUp = Color(0xFFE53935); // Red - pre-movement
  static const Color onTheMove = Color(0xFFFF8F00); // Amber - in-transit
  static const Color delivered = Color(0xFF4CAF50); // Green - delivered
  static const Color deliveredToStorage = Color(0xFF4CAF50); // Green - delivered

  // ========================================
  // Order Direction Colors
  // ========================================
  static const Color orderDirectionOutbound = Color(0xFFFF9800); // Orange
  static const Color orderDirectionInboundRep = Color(0xFF009688); // Teal
  static const Color orderDirectionInboundExternal = Color(0xFF3F51B5); // Indigo
}
