import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors/app_colors.dart';
import 'typography/text_styles.dart';
import 'spacing/app_spacing.dart';
import 'constants/app_constants.dart';
import 'constants/app_dimensions.dart';

/// Light theme configuration for URA CORE application.
/// Uses Material Design 3 principles with teal brand color.
class ThemeDataLight {
  const ThemeDataLight._();

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: _buildAppBarThemeData(),
      cardTheme: _buildCardThemeData(),
      elevatedButtonTheme: _buildElevatedButtonThemeData(),
      textButtonTheme: _buildTextButtonThemeData(),
      outlinedButtonTheme: _buildOutlinedButtonThemeData(),
      inputDecorationTheme: _buildInputDecorationThemeData(),
      bottomNavigationBarTheme: _buildBottomNavigationBarThemeData(),
      floatingActionButtonTheme: _buildFloatingActionButtonThemeData(),
      chipTheme: _buildChipThemeData(),
      dialogTheme: _buildDialogThemeData(),
      bottomSheetTheme: _buildBottomSheetThemeData(),
      dividerTheme: _buildDividerThemeData(),
      progressIndicatorTheme: _buildProgressIndicatorThemeData(),
      snackBarTheme: _buildSnackBarThemeData(),
      tabBarTheme: _buildTabBarThemeData(),
    );
  }

  static TextTheme _buildTextTheme() {
    return GoogleFonts.cairoTextTheme().copyWith(
      displayLarge: AppTextStyles.displayLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      displayMedium: AppTextStyles.displayMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      displaySmall: AppTextStyles.displaySmall.copyWith(
        color: AppColors.textPrimary,
      ),
      headlineLarge: AppTextStyles.headlineLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      headlineMedium: AppTextStyles.headlineMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      headlineSmall: AppTextStyles.headlineSmall.copyWith(
        color: AppColors.textPrimary,
      ),
      titleLarge: AppTextStyles.titleLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      titleMedium: AppTextStyles.titleMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      titleSmall: AppTextStyles.titleSmall.copyWith(
        color: AppColors.textPrimary,
      ),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      bodySmall: AppTextStyles.bodySmall.copyWith(
        color: AppColors.textSecondary,
      ),
      labelLarge: AppTextStyles.labelLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      labelMedium: AppTextStyles.labelMedium.copyWith(
        color: AppColors.textSecondary,
      ),
      labelSmall: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textTertiary,
      ),
    );
  }

  static AppBarTheme _buildAppBarThemeData() {
    return AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: AppConstants.elevation0,
      centerTitle: false,
      iconTheme: IconThemeData(
        color: AppColors.primary,
      ),
      actionsIconTheme: IconThemeData(
        color: AppColors.primary,
      ),
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: AppColors.textPrimary,
      ),
    );
  }

  static CardThemeData _buildCardThemeData() {
    return CardThemeData(
      color: AppColors.white,
      elevation: AppConstants.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
      ),
      margin: AppSpacing.horizontalLargePadding +
          AppSpacing.verticalSmallPadding,
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonThemeData() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: AppColors.grey300,
        disabledForegroundColor: AppColors.textDisabled,
        elevation: AppConstants.elevation0,
        minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
        padding: AppSpacing.horizontalLargePadding +
            AppSpacing.verticalMediumPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppConstants.borderRadiusMediumRadius,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    );
  }

  static TextButtonThemeData _buildTextButtonThemeData() {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textDisabled,
        padding: AppSpacing.horizontalLargePadding +
            AppSpacing.verticalMediumPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppConstants.borderRadiusMediumRadius,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonThemeData() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textDisabled,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
        padding: AppSpacing.horizontalLargePadding +
            AppSpacing.verticalMediumPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppConstants.borderRadiusMediumRadius,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationThemeData() {
    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.primary.withValues(alpha: 0.09),
      contentPadding: AppSpacing.horizontalLargePadding +
          AppSpacing.verticalMediumPadding,
      border: OutlineInputBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        borderSide: BorderSide.none,
      ),
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textSecondary,
      ),
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textTertiary,
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(
        color: AppColors.error,
      ),
    );
  }

  static BottomNavigationBarThemeData _buildBottomNavigationBarThemeData() {
    return BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.grey600,
      selectedLabelStyle: AppTextStyles.labelMedium,
      unselectedLabelStyle: AppTextStyles.labelMedium,
      type: BottomNavigationBarType.fixed,
      elevation: AppConstants.elevation3,
    );
  }

  static FloatingActionButtonThemeData _buildFloatingActionButtonThemeData() {
    return FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textOnPrimary,
      elevation: AppConstants.elevation3,
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusLargeRadius,
      ),
    );
  }

  static ChipThemeData _buildChipThemeData() {
    return ChipThemeData(
      backgroundColor: AppColors.grey100,
      deleteIconColor: AppColors.grey600,
      disabledColor: AppColors.grey200,
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      secondarySelectedColor: AppColors.primary.withValues(alpha: 0.12),
      padding: AppSpacing.horizontalMediumPadding,
      labelStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      brightness: Brightness.light,
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusSmallRadius,
      ),
    );
  }

  static DialogThemeData _buildDialogThemeData() {
    return DialogThemeData(
      backgroundColor: AppColors.white,
      elevation: AppConstants.elevation8,
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusLargeRadius,
      ),
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textPrimary,
      ),
    );
  }

  static BottomSheetThemeData _buildBottomSheetThemeData() {
    return BottomSheetThemeData(
      backgroundColor: AppColors.white,
      elevation: AppConstants.elevation8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.borderRadiusLarge),
        ),
      ),
    );
  }

  static DividerThemeData _buildDividerThemeData() {
    return DividerThemeData(
      color: AppColors.grey200,
      thickness: AppDimensions.dividerThickness,
      space: 1,
    );
  }

  static ProgressIndicatorThemeData _buildProgressIndicatorThemeData() {
    return const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.grey200,
      circularTrackColor: AppColors.grey200,
    );
  }

  static SnackBarThemeData _buildSnackBarThemeData() {
    return SnackBarThemeData(
      backgroundColor: AppColors.grey900,
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: AppConstants.elevation6,
    );
  }

  static TabBarThemeData _buildTabBarThemeData() {
    return TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.grey600,
      labelStyle: AppTextStyles.labelLarge,
      unselectedLabelStyle: AppTextStyles.labelLarge,
      indicator: UnderlineTabIndicator(
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: 2,
        ),
        insets: AppSpacing.horizontalLargePadding,
      ),
    );
  }
}
