import 'package:flutter/material.dart';
import 'brand_colors.dart';
import 'semantic_colors.dart';
import 'order_status_colors.dart';
import 'neutral_colors.dart';

/// Centralized color system for URA CORE application.
/// Provides access to all color categories through a single entry point.
class AppColors {
  const AppColors._();

  // ========================================
  // Brand Colors
  // ========================================
  static const Color primary = BrandColors.primary;
  static const Color primaryDark = BrandColors.primaryDark;
  static const Color primaryLight = BrandColors.primaryLight;
  static const Color accent = BrandColors.accent;
  static const Color accentDark = BrandColors.accentDark;

  // ========================================
  // Semantic Colors (Status)
  // ========================================
  static const Color success = SemanticColors.success;
  static const Color successLight = SemanticColors.successLight;
  static const Color successDark = SemanticColors.successDark;

  static const Color error = SemanticColors.error;
  static const Color errorLight = SemanticColors.errorLight;
  static const Color errorDark = SemanticColors.errorDark;

  static const Color warning = SemanticColors.warning;
  static const Color warningLight = SemanticColors.warningLight;
  static const Color warningDark = SemanticColors.warningDark;

  static const Color info = SemanticColors.info;
  static const Color infoLight = SemanticColors.infoLight;
  static const Color infoDark = SemanticColors.infoDark;

  // ========================================
  // Order Status Colors (Traffic Light)
  // ========================================
  static const Color orderStatusAssigned = OrderStatusColors.assigned;
  static const Color orderStatusPickedUp = OrderStatusColors.pickedUp;
  static const Color orderStatusOnTheMove = OrderStatusColors.onTheMove;
  static const Color orderStatusDelivered = OrderStatusColors.delivered;
  static const Color orderStatusDeliveredToStorage = OrderStatusColors.deliveredToStorage;

  // ========================================
  // Order Direction Colors
  // ========================================
  static const Color orderDirectionOutbound = OrderStatusColors.orderDirectionOutbound;
  static const Color orderDirectionInboundRep = OrderStatusColors.orderDirectionInboundRep;
  static const Color orderDirectionInboundExternal = OrderStatusColors.orderDirectionInboundExternal;

  // ========================================
  // Neutral Colors
  // ========================================
  static const Color white = NeutralColors.white;
  static const Color black = NeutralColors.black;

  static const Color grey50 = NeutralColors.grey50;
  static const Color grey100 = NeutralColors.grey100;
  static const Color grey200 = NeutralColors.grey200;
  static const Color grey300 = NeutralColors.grey300;
  static const Color grey400 = NeutralColors.grey400;
  static const Color grey500 = NeutralColors.grey500;
  static const Color grey600 = NeutralColors.grey600;
  static const Color grey700 = NeutralColors.grey700;
  static const Color grey800 = NeutralColors.grey800;
  static const Color grey900 = NeutralColors.grey900;

  // ========================================
  // Surface Colors
  // ========================================
  static const Color surface = NeutralColors.white;
  static const Color surfaceVariant = NeutralColors.grey100;
  static const Color surfaceContainer = NeutralColors.grey50;
  static const Color surfaceContainerLow = NeutralColors.grey50;
  static const Color surfaceContainerHigh = NeutralColors.grey200;

  // ========================================
  // Background Colors
  // ========================================
  static const Color background = NeutralColors.grey50;
  static const Color backgroundVariant = NeutralColors.grey100;

  // ========================================
  // Text Colors
  // ========================================
  static const Color textPrimary = NeutralColors.grey900;
  static const Color textSecondary = NeutralColors.grey700;
  static const Color textTertiary = NeutralColors.grey500;
  static const Color textDisabled = NeutralColors.grey400;
  static const Color textOnPrimary = NeutralColors.white;
  static const Color textOnError = NeutralColors.white;
  static const Color textOnSuccess = NeutralColors.white;
  static const Color textOnWarning = NeutralColors.grey900;
  static const Color textOnInfo = NeutralColors.white;

  // ========================================
  // Border Colors
  // ========================================
  static const Color border = NeutralColors.grey300;
  static const Color borderLight = NeutralColors.grey200;
  static const Color borderDark = NeutralColors.grey400;
  static const Color borderFocus = BrandColors.primary;
  static const Color borderError = SemanticColors.error;

  // ========================================
  // Icon Colors
  // ========================================
  static const Color iconPrimary = NeutralColors.grey900;
  static const Color iconSecondary = NeutralColors.grey700;
  static const Color iconDisabled = NeutralColors.grey400;
  static const Color iconOnPrimary = NeutralColors.white;

  // ========================================
  // Overlay Colors
  // ========================================
  static const Color overlay = Color(0x80000000);
  static const Color overlayLight = Color(0x40000000);
}
