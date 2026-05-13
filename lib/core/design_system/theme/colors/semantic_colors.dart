import 'package:flutter/material.dart';

/// Semantic colors for status messages and feedback.
/// Provides success, error, warning, and info color variants.
class SemanticColors {
  const SemanticColors._();

  // ========================================
  // Success Colors
  // ========================================
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF81C784);
  static const Color successDark = Color(0xFF388E3C);

  // ========================================
  // Error Colors
  // ========================================
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorDark = Color(0xFFD32F2F);

  // ========================================
  // Warning Colors
  // ========================================
  static const Color warning = Color(0xFFFFB300);
  static const Color warningLight = Color(0xFFFFCA28);
  static const Color warningDark = Color(0xFFFFA000);

  // ========================================
  // Info Colors
  // ========================================
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFF64B5F6);
  static const Color infoDark = Color(0xFF1976D2);
}
