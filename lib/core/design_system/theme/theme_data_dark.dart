import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors/app_colors.dart';
import 'typography/text_styles.dart';
import 'spacing/app_spacing.dart';
import 'constants/app_constants.dart';
import 'constants/app_dimensions.dart';

/// Dark theme configuration for URA CORE application.
/// Uses Material Design 3 principles with teal brand color.
class ThemeDataDark {
  const ThemeDataDark._();

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.grey900,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: _buildAppBarTheme(),
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
        color: AppColors.white,
      ),
      displayMedium: AppTextStyles.displayMedium.copyWith(
        color: AppColors.white,
      ),
      displaySmall: AppTextStyles.displaySmall.copyWith(
        color: AppColors.white,
      ),
      headlineLarge: AppTextStyles.headlineLarge.copyWith(
        color: AppColors.white,
      ),
      headlineMedium: AppTextStyles.headlineMedium.copyWith(
        color: AppColors.white,
      ),
      headlineSmall: AppTextStyles.headlineSmall.copyWith(
        color: AppColors.white,
      ),
      titleLarge: AppTextStyles.titleLarge.copyWith(
        color: AppColors.white,
      ),
      titleMedium: AppTextStyles.titleMedium.copyWith(
        color: AppColors.white,
      ),
      titleSmall: AppTextStyles.titleSmall.copyWith(
        color: AppColors.white,
      ),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(
        color: AppColors.grey300,
      ),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.grey300,
      ),
      bodySmall: AppTextStyles.bodySmall.copyWith(
        color: AppColors.grey400,
      ),
      labelLarge: AppTextStyles.labelLarge.copyWith(
        color: AppColors.white,
      ),
      labelMedium: AppTextStyles.labelMedium.copyWith(
        color: AppColors.grey400,
      ),
      labelSmall: AppTextStyles.labelSmall.copyWith(
        color: AppColors.grey500,
      ),
    );
  }

  static AppBarTheme _buildAppBarTheme() {
    return AppBarTheme(
      backgroundColor: AppColors.grey800,
      foregroundColor: AppColors.white,
      elevation: AppConstants.elevation0,
      centerTitle: false,
      iconTheme: IconThemeData(
        color: AppColors.white,
      ),
      actionsIconTheme: IconThemeData(
        color: AppColors.white,
      ),
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: AppColors.white,
      ),
    );
  }

  static CardThemeData _buildCardThemeData() {
    return CardThemeData(
      color: AppColors.grey800,
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
        disabledBackgroundColor: AppColors.grey700,
        disabledForegroundColor: AppColors.grey600,
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
        disabledForegroundColor: AppColors.grey600,
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
        disabledForegroundColor: AppColors.grey600,
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
      fillColor: AppColors.grey700,
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
        color: AppColors.grey400,
      ),
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.grey500,
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(
        color: AppColors.error,
      ),
    );
  }

  static BottomNavigationBarThemeData _buildBottomNavigationBarThemeData() {
    return BottomNavigationBarThemeData(
      backgroundColor: AppColors.grey800,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.grey400,
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
      backgroundColor: AppColors.grey700,
      deleteIconColor: AppColors.grey400,
      disabledColor: AppColors.grey800,
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      secondarySelectedColor: AppColors.primary.withValues(alpha: 0.12),
      padding: AppSpacing.horizontalMediumPadding,
      labelStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.white,
      ),
      secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.white,
      ),
      brightness: Brightness.dark,
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusSmallRadius,
      ),
    );
  }

  static DialogThemeData _buildDialogThemeData() {
    return DialogThemeData(
      backgroundColor: AppColors.grey800,
      elevation: AppConstants.elevation8,
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusLargeRadius,
      ),
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: AppColors.white,
      ),
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.grey300,
      ),
    );
  }

  static BottomSheetThemeData _buildBottomSheetThemeData() {
    return BottomSheetThemeData(
      backgroundColor: AppColors.grey800,
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
      color: AppColors.grey700,
      thickness: AppDimensions.dividerThickness,
      space: 1,
    );
  }

  static ProgressIndicatorThemeData _buildProgressIndicatorThemeData() {
    return const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.grey700,
      circularTrackColor: AppColors.grey700,
    );
  }

  static SnackBarThemeData _buildSnackBarThemeData() {
    return SnackBarThemeData(
      backgroundColor: AppColors.grey800,
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
      unselectedLabelColor: AppColors.grey400,
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
