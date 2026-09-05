import 'package:flutter/material.dart';
import 'material_theme.dart';
import 'theme_util.dart';

/// Centralized Design System for Altr Stream Admin Portal.
/// Encapsulates Material 3 light/dark themes, component themes, and semantic operational status tokens.
class AppTheme {
  // --- SEMANTIC OPERATIONAL STATUS COLORS ---
  static const Color success = Color(0xFF15803D);       // Green 700
  static const Color successLight = Color(0xFF16A34A);  // Green 600
  static const Color successDark = Color(0xFF4ADE80);   // Green 400

  static const Color error = Color(0xFFDC2626);         // Red 600
  static const Color errorLight = Color(0xFFEF4444);    // Red 500
  static const Color errorDark = Color(0xFFF87171);     // Red 400

  static const Color warning = Color(0xFFD97706);       // Amber 600
  static const Color warningLight = Color(0xFFF59E0B);  // Amber 500
  static const Color warningDark = Color(0xFFFBBF24);   // Amber 400

  static const Color info = Color(0xFF0284C7);          // Sky 600
  static const Color infoLight = Color(0xFF38BDF8);     // Sky 400
  static const Color infoDark = Color(0xFF38BDF8);      // Sky 400

  // Status background alpha helpers
  static Color successBg(BuildContext context) =>
      _statusBg(Theme.of(context).brightness == Brightness.dark ? successDark : successLight, context);

  static Color errorBg(BuildContext context) =>
      _statusBg(Theme.of(context).brightness == Brightness.dark ? errorDark : errorLight, context);

  static Color warningBg(BuildContext context) =>
      _statusBg(Theme.of(context).brightness == Brightness.dark ? warningDark : warningLight, context);

  static Color infoBg(BuildContext context) =>
      _statusBg(Theme.of(context).brightness == Brightness.dark ? infoDark : infoLight, context);

  static Color _statusBg(Color color, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return color.withValues(alpha: isDark ? 0.18 : 0.12);
  }

  // Helper to get status color based on active brightness
  static Color getStatusColor(String status, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status.toUpperCase()) {
      case 'ACTIVE':
      case 'HEALTHY':
        return isDark ? successDark : successLight;
      case 'DEGRADED':
      case 'WARNING':
        return isDark ? warningDark : warningLight;
      case 'ERROR':
      case 'UNREACHABLE':
        return isDark ? errorDark : errorLight;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  // --- THEME BUILDERS ---

  static final MaterialTheme _materialTheme = MaterialTheme(
    createTextTheme(null),
  );

  /// Global Light Theme
  static ThemeData get lightTheme {
    final scheme = MaterialTheme.lightScheme();
    final baseTheme = _materialTheme.theme(scheme);
    return _applyComponentThemes(baseTheme, scheme);
  }

  /// Global Dark Theme
  static ThemeData get darkTheme {
    final scheme = MaterialTheme.darkScheme();
    final baseTheme = _materialTheme.theme(scheme);
    return _applyComponentThemes(baseTheme, scheme);
  }

  static ThemeData _applyComponentThemes(ThemeData base, ColorScheme scheme) {
    return base.copyWith(
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 13,
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }
}
