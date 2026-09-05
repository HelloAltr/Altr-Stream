import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Generates a unified [TextTheme] using Nunito Sans for body/labels and Nunito for headings.
/// Includes graceful fallback to standard system typography when offline or self-hosted.
TextTheme createTextTheme(
  BuildContext? context, {
  String bodyFont = 'Nunito Sans',
  String displayFont = 'Nunito',
  TextTheme? baseTextTheme,
}) {
  final base = baseTextTheme ??
      (context != null ? Theme.of(context).textTheme : Typography.material2021().englishLike);

  TextTheme bodyTheme;
  TextTheme displayTheme;

  try {
    bodyTheme = GoogleFonts.getTextTheme(bodyFont, base);
    displayTheme = GoogleFonts.getTextTheme(displayFont, base);
  } catch (_) {
    // Fallback to base text theme if font loading fails
    bodyTheme = base;
    displayTheme = base;
  }

  return displayTheme.copyWith(
    bodyLarge: bodyTheme.bodyLarge,
    bodyMedium: bodyTheme.bodyMedium,
    bodySmall: bodyTheme.bodySmall,
    labelLarge: bodyTheme.labelLarge,
    labelMedium: bodyTheme.labelMedium,
    labelSmall: bodyTheme.labelSmall,
  );
}
