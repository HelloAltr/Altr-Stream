import 'package:flutter/material.dart';

/// Altr Stream design tokens and color palette.
///
/// Shared across macOS and Windows desktop targets for visual consistency.
class AltrColors {
  AltrColors._();

  // Backgrounds
  static const Color windowBackground = Color(0xFF191D26);
  static const Color titleBarBackground = Color(0xFF252B37);
  static const Color panelBackground = Color(0xFF151B25);
  static const Color cardBackground = Color(0xFF1C2330);

  // Borders & Dividers
  static const Color border = Color(0xFF303744);
  static const Color dropdownBorder = Color(0xFF3A4352);
  static const Color divider = Color(0xFF252B37);

  // Primary & Accents
  static const Color primaryBlue = Color(0xFF0878F9);
  static const Color primaryBlueHover = Color(0xFF2386FB);
  static const Color linkBlue = Color(0xFF35AAFF);

  // Status Indicators
  static const Color successGreen = Color(0xFF20DC79);
  static const Color warningOrange = Color(0xFFFF9F2F);
  static const Color errorRed = Color(0xFFFF5B61);

  // Buttons & Controls
  static const Color secondaryButton = Color(0xFF3B404C);
  static const Color secondaryButtonHover = Color(0xFF4A5160);
  static const Color dropdownBackground = Color(0xFF1C2330);

  // Typography
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFFAEB7C7);
  static const Color descriptionText = Color(0xFFC0C7D5);
  static const Color textMuted = Color(0xFF758195);
}

/// Dimensions, radii, and spacing constants.
class AltrDimensions {
  AltrDimensions._();

  // Window default dimensions
  static const double windowWidth = 868.0;
  static const double windowHeight = 662.0;
  static const double windowMinWidth = 720.0;
  static const double windowMinHeight = 560.0;

  // Insets
  static const double horizontalInset = 32.0;
  static const double verticalPadding = 24.0;
  static const double panelPaddingHorizontal = 20.0;
  static const double panelPaddingVertical = 4.0;

  // Corner Radii
  static const double windowRadius = 14.0;
  static const double panelRadius = 10.0;
  static const double buttonRadius = 6.0;
  static const double cardRadius = 8.0;

  // Heights
  static const double rowHeight = 42.0;
  static const double rowExpandedMinHeight = 74.0;
  static const double buttonHeight = 36.0;
  static const double tableButtonHeight = 30.0;
  static const double dropdownHeight = 30.0;
}

/// Dark theme configuration for Altr Stream Manager desktop app.
class AltrTheme {
  AltrTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AltrColors.windowBackground,
      colorScheme: const ColorScheme.dark(
        primary: AltrColors.primaryBlue,
        secondary: AltrColors.secondaryButton,
        surface: AltrColors.panelBackground,
        error: AltrColors.errorRed,
        onPrimary: Colors.white,
        onSurface: AltrColors.textPrimary,
      ),
      dividerColor: AltrColors.border,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AltrColors.textPrimary,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AltrColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AltrColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AltrColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: AltrColors.secondaryText,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: AltrColors.descriptionText,
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AltrColors.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, AltrDimensions.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AltrDimensions.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
