import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff4e662a),
      surfaceTint: Color(0xff4e662a),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffcfeda1),
      onPrimaryContainer: Color(0xff374e14),
      secondary: Color(0xff586420),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffdcea97),
      onSecondaryContainer: Color(0xff414b08),
      tertiary: Color(0xff636117),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffeae78e),
      onTertiaryContainer: Color(0xff4a4900),
      error: Color(0xff904b3d),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffffdad3),
      onErrorContainer: Color(0xff733428),
      surface: Color(0xfff9faef),
      onSurface: Color(0xff1a1c16),
      onSurfaceVariant: Color(0xff4e4539),
      outline: Color(0xff807667),
      outlineVariant: Color(0xffd2c5b4),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff2f312a),
      inversePrimary: Color(0xffb3d088),
      primaryFixed: Color(0xffcfeda1),
      onPrimaryFixed: Color(0xff111f00),
      primaryFixedDim: Color(0xffb3d088),
      onPrimaryFixedVariant: Color(0xff374e14),
      secondaryFixed: Color(0xffdcea97),
      onSecondaryFixed: Color(0xff181e00),
      secondaryFixedDim: Color(0xffc0ce7e),
      onSecondaryFixedVariant: Color(0xff414b08),
      tertiaryFixed: Color(0xffeae78e),
      onTertiaryFixed: Color(0xff1d1d00),
      tertiaryFixedDim: Color(0xffcdca75),
      onTertiaryFixedVariant: Color(0xff4a4900),
      surfaceDim: Color(0xffdadbd0),
      surfaceBright: Color(0xfff9faef),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfff4f4e9),
      surfaceContainer: Color(0xffeeefe3),
      surfaceContainerHigh: Color(0xffe8e9de),
      surfaceContainerHighest: Color(0xffe2e3d8),
    );
  }

  ThemeData light() {
    return theme(lightScheme());
  }

  static ColorScheme lightMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff273c04),
      surfaceTint: Color(0xff4e662a),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff5c7537),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff313a00),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff67732d),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff393800),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff727025),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff5e2419),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffa1594a),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfff9faef),
      onSurface: Color(0xff10120c),
      onSurfaceVariant: Color(0xff3d3529),
      outline: Color(0xff5a5144),
      outlineVariant: Color(0xff766c5d),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff2f312a),
      inversePrimary: Color(0xffb3d088),
      primaryFixed: Color(0xff5c7537),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff445c21),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff67732d),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff4f5a17),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff727025),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff59570c),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffc6c7bc),
      surfaceBright: Color(0xfff9faef),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfff4f4e9),
      surfaceContainer: Color(0xffe8e9de),
      surfaceContainerHigh: Color(0xffddded2),
      surfaceContainerHighest: Color(0xffd1d2c7),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme());
  }

  static ColorScheme lightHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff1e3200),
      surfaceTint: Color(0xff4e662a),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff395016),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff282f00),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff434e0b),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff2f2e00),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff4d4b00),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff511a10),
      onError: Color(0xffffffff),
      errorContainer: Color(0xff76362a),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfff9faef),
      onSurface: Color(0xff000000),
      onSurfaceVariant: Color(0xff000000),
      outline: Color(0xff322b20),
      outlineVariant: Color(0xff51483b),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff2f312a),
      inversePrimary: Color(0xffb3d088),
      primaryFixed: Color(0xff395016),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff233901),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff434e0b),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff2e3600),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff4d4b00),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff353400),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffb8baaf),
      surfaceBright: Color(0xfff9faef),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfff1f2e6),
      surfaceContainer: Color(0xffe2e3d8),
      surfaceContainerHigh: Color(0xffd4d5ca),
      surfaceContainerHighest: Color(0xffc6c7bc),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme());
  }

  static ColorScheme darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffb3d088),
      surfaceTint: Color(0xffb3d088),
      onPrimary: Color(0xff213600),
      primaryContainer: Color(0xff374e14),
      onPrimaryContainer: Color(0xffcfeda1),
      secondary: Color(0xffc0ce7e),
      onSecondary: Color(0xff2c3400),
      secondaryContainer: Color(0xff414b08),
      onSecondaryContainer: Color(0xffdcea97),
      tertiary: Color(0xffcdca75),
      onTertiary: Color(0xff333200),
      tertiaryContainer: Color(0xff4a4900),
      onTertiaryContainer: Color(0xffeae78e),
      error: Color(0xffffb4a5),
      onError: Color(0xff561f14),
      errorContainer: Color(0xff733428),
      onErrorContainer: Color(0xffffdad3),
      surface: Color(0xff12140e),
      onSurface: Color(0xffe2e3d8),
      onSurfaceVariant: Color(0xffd2c5b4),
      outline: Color(0xff9a8f80),
      outlineVariant: Color(0xff4e4539),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffe2e3d8),
      inversePrimary: Color(0xff4e662a),
      primaryFixed: Color(0xffcfeda1),
      onPrimaryFixed: Color(0xff111f00),
      primaryFixedDim: Color(0xffb3d088),
      onPrimaryFixedVariant: Color(0xff374e14),
      secondaryFixed: Color(0xffdcea97),
      onSecondaryFixed: Color(0xff181e00),
      secondaryFixedDim: Color(0xffc0ce7e),
      onSecondaryFixedVariant: Color(0xff414b08),
      tertiaryFixed: Color(0xffeae78e),
      onTertiaryFixed: Color(0xff1d1d00),
      tertiaryFixedDim: Color(0xffcdca75),
      onTertiaryFixedVariant: Color(0xff4a4900),
      surfaceDim: Color(0xff12140e),
      surfaceBright: Color(0xff383a32),
      surfaceContainerLowest: Color(0xff0d0f09),
      surfaceContainerLow: Color(0xff1a1c16),
      surfaceContainer: Color(0xff1e2019),
      surfaceContainerHigh: Color(0xff282b24),
      surfaceContainerHighest: Color(0xff33362e),
    );
  }

  ThemeData dark() {
    return theme(darkScheme());
  }

  static ColorScheme darkMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffc9e79c),
      surfaceTint: Color(0xffb3d088),
      onPrimary: Color(0xff192a00),
      primaryContainer: Color(0xff7f9a57),
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xffd6e491),
      onSecondary: Color(0xff222900),
      secondaryContainer: Color(0xff8b974d),
      onSecondaryContainer: Color(0xff000000),
      tertiary: Color(0xffe3e089),
      onTertiary: Color(0xff282700),
      tertiaryContainer: Color(0xff969445),
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xffffd2c9),
      onError: Color(0xff48140a),
      errorContainer: Color(0xffcc7b6b),
      onErrorContainer: Color(0xff000000),
      surface: Color(0xff12140e),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xffe8dac9),
      outline: Color(0xffbcb0a0),
      outlineVariant: Color(0xff9a8f7f),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffe2e3d8),
      inversePrimary: Color(0xff384f15),
      primaryFixed: Color(0xffcfeda1),
      onPrimaryFixed: Color(0xff0a1400),
      primaryFixedDim: Color(0xffb3d088),
      onPrimaryFixedVariant: Color(0xff273c04),
      secondaryFixed: Color(0xffdcea97),
      onSecondaryFixed: Color(0xff0f1300),
      secondaryFixedDim: Color(0xffc0ce7e),
      onSecondaryFixedVariant: Color(0xff313a00),
      tertiaryFixed: Color(0xffeae78e),
      onTertiaryFixed: Color(0xff121200),
      tertiaryFixedDim: Color(0xffcdca75),
      onTertiaryFixedVariant: Color(0xff393800),
      surfaceDim: Color(0xff12140e),
      surfaceBright: Color(0xff43453d),
      surfaceContainerLowest: Color(0xff060804),
      surfaceContainerLow: Color(0xff1c1e18),
      surfaceContainer: Color(0xff262921),
      surfaceContainerHigh: Color(0xff31332c),
      surfaceContainerHighest: Color(0xff3c3f37),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme());
  }

  static ColorScheme darkHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffdcfaae),
      surfaceTint: Color(0xffb3d088),
      onPrimary: Color(0xff000000),
      primaryContainer: Color(0xffb0cc84),
      onPrimaryContainer: Color(0xff060e00),
      secondary: Color(0xffeaf8a3),
      onSecondary: Color(0xff000000),
      secondaryContainer: Color(0xffbcca7a),
      onSecondaryContainer: Color(0xff090d00),
      tertiary: Color(0xfff7f49a),
      onTertiary: Color(0xff000000),
      tertiaryContainer: Color(0xffc9c672),
      onTertiaryContainer: Color(0xff0c0c00),
      error: Color(0xffffece8),
      onError: Color(0xff000000),
      errorContainer: Color(0xffffaf9e),
      onErrorContainer: Color(0xff200100),
      surface: Color(0xff12140e),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xffffffff),
      outline: Color(0xfffceedc),
      outlineVariant: Color(0xffcec1b0),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffe2e3d8),
      inversePrimary: Color(0xff384f15),
      primaryFixed: Color(0xffcfeda1),
      onPrimaryFixed: Color(0xff000000),
      primaryFixedDim: Color(0xffb3d088),
      onPrimaryFixedVariant: Color(0xff0a1400),
      secondaryFixed: Color(0xffdcea97),
      onSecondaryFixed: Color(0xff000000),
      secondaryFixedDim: Color(0xffc0ce7e),
      onSecondaryFixedVariant: Color(0xff0f1300),
      tertiaryFixed: Color(0xffeae78e),
      onTertiaryFixed: Color(0xff000000),
      tertiaryFixedDim: Color(0xffcdca75),
      onTertiaryFixedVariant: Color(0xff121200),
      surfaceDim: Color(0xff12140e),
      surfaceBright: Color(0xff4f5149),
      surfaceContainerLowest: Color(0xff000000),
      surfaceContainerLow: Color(0xff1e2019),
      surfaceContainer: Color(0xff2f312a),
      surfaceContainerHigh: Color(0xff3a3c34),
      surfaceContainerHighest: Color(0xff45483f),
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme());
  }


  ThemeData theme(ColorScheme colorScheme) => ThemeData(
     useMaterial3: true,
     brightness: colorScheme.brightness,
     colorScheme: colorScheme,
     textTheme: textTheme.apply(
       bodyColor: colorScheme.onSurface,
       displayColor: colorScheme.onSurface,
     ),
     scaffoldBackgroundColor: colorScheme.surface,
     canvasColor: colorScheme.surface,
  );


  List<ExtendedColor> get extendedColors => [
  ];
}

class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
