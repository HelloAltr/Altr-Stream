import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Backgrounds & Surfaces
  static const Color bgPrimary = Color(0xFF0B0F19);      // Deep Slate Canvas
  static const Color bgSecondary = Color(0xFF111827);    // Sidebar / Card Background
  static const Color bgSidebar = Color(0xFF0F172A);      // Dedicated Sidebar Surface
  static const Color bgCard = Color(0xFF131C2E);         // Card Surface
  static const Color bgCardHover = Color(0xFF1A263D);    // Card Hover Surface
  static const Color bgInput = Color(0xFF0B0F19);        // Input Field Surface
  
  // Borders & Lines
  static const Color borderColor = Color(0xFF1E293B);    // Subtle borders
  static const Color borderSubtle = Color(0xFF162032);   // Very light dividers
  static const Color borderFocus = Color(0xFF38BDF8);    // Cyan Focus Highlight

  // Typography Colors
  static const Color textPrimary = Color(0xFFF8FAFC);    // High contrast white-slate
  static const Color textSecondary = Color(0xFF94A3B8);  // Slate secondary
  static const Color textMuted = Color(0xFF64748B);      // Muted metadata

  // Brand Accents
  static const Color accentBlue = Color(0xFF0284C7);     // Primary Blue
  static const Color accentBlueHover = Color(0xFF0369A1);
  static const Color accentCyan = Color(0xFF38BDF8);     // Vibrant Cyan accent
  static const Color accentCyanSubtle = Color(0x1A38BDF8);

  // Status & Feedback Colors
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0x1F10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color errorBg = Color(0x1FEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0x1FF59E0B);
  static const Color info = Color(0xFF38BDF8);
  static const Color infoBg = Color(0x1F38BDF8);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      primaryColor: accentBlue,
      colorScheme: const ColorScheme.dark(
        primary: accentBlue,
        secondary: accentCyan,
        surface: bgSecondary,
        error: error,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: borderColor),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 13),
        labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme.copyWith(
          displayLarge: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.bold),
          displayMedium: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.bold),
          titleLarge: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 20),
          titleMedium: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
          titleSmall: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
          bodyLarge: GoogleFonts.inter(color: textPrimary, fontSize: 14),
          bodyMedium: GoogleFonts.inter(color: textSecondary, fontSize: 13),
          bodySmall: GoogleFonts.inter(color: textMuted, fontSize: 12),
        ),
      ),
    );
  }
}
