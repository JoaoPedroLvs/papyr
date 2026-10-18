import 'package:flutter/material.dart';

/// The logo's colors, the same in both themes.
abstract final class Brand {
  static const navy = Color(0xFF102E50);
  static const sky = Color(0xFF32B0FA);
  static const green = Color(0xFF00FD9A);
  static const paper = Color(0xFFF6F3EC);
  static const night = Color(0xFF0E1A2A);
}

/// Newsreader 500 at its own optical size: Flutter does not set opsz by itself, so without it the title gets the text cut (opsz 18).
TextStyle serif(double size, {double? height}) => TextStyle(
  fontFamily: 'Newsreader',
  fontSize: size,
  height: height,
  fontWeight: FontWeight.w500,
  fontVariations: [FontVariation('opsz', size), const FontVariation('wght', 500)],
);

/// "Papel e tinta" (spec §5): the scheme is built by hand from the brand colors, never from a seed.
ThemeData papyrTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFF1EEE6) : Brand.navy;
  final onInk = dark ? Brand.navy : Brand.paper;
  final panel = dark ? const Color(0xFF1A2B42) : const Color(0xFFEEE9DD);
  final pill = dark ? const Color(0xFF1E3150) : const Color(0xFFE8E2D4);
  final s = ColorScheme(
    brightness: brightness,
    surface: dark ? Brand.night : Brand.paper,
    primary: ink,
    onSurface: ink,
    inverseSurface: ink,
    onPrimary: onInk,
    onInverseSurface: onInk,
    primaryContainer: dark ? const Color(0xFF1F3A5F) : Brand.navy,
    onPrimaryContainer: Brand.paper,
    surfaceContainerLowest: dark ? const Color(0xFF16263B) : Colors.white,
    surfaceContainerLow: panel,
    surfaceContainer: panel,
    surfaceContainerHigh: pill,
    surfaceContainerHighest: pill,
    outlineVariant: dark ? const Color(0xFF24364F) : const Color(0xFFE6E1D6),
    onSurfaceVariant: dark ? const Color(0xFFA3ADBB) : const Color(0xFF6B655A),
    outline: dark ? const Color(0xFF7F8DA3) : const Color(0xFF8A8376),
    secondary: Brand.sky,
    onSecondary: Brand.navy,
    tertiary: Brand.green,
    onTertiary: Brand.navy,
    error: dark ? const Color(0xFFF2B8B5) : const Color(0xFFB3261E),
    onError: dark ? const Color(0xFF601410) : Colors.white,
    surfaceTint: Colors.transparent,
  );
  final r14 = BorderRadius.circular(14);
  return ThemeData(
    colorScheme: s,
    fontFamily: 'Outfit',
    scaffoldBackgroundColor: s.surface,
    textTheme: TextTheme(
      headlineLarge: serif(34, height: 1.05).copyWith(letterSpacing: -0.34),
      headlineMedium: serif(28, height: 1.1),
      titleMedium: const TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w500, color: s.onSurfaceVariant),
      bodyLarge: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w400),
      bodyMedium: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w400, color: s.onSurfaceVariant),
      labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(64, 52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: s.outlineVariant)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: s.primary,
        selectedForegroundColor: s.onPrimary,
        side: BorderSide(color: s.outlineVariant),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r14),
      backgroundColor: s.inverseSurface,
      elevation: 0,
    ),
    // AlertDialog uses titleTextStyle as-is, so it carries its own color
    dialogTheme: DialogThemeData(
      backgroundColor: s.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: serif(22, height: 1.2).copyWith(color: s.onSurface),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: r14),
      elevation: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: s.surfaceContainer,
      border: OutlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: s.secondary, width: 2)),
    ),
  );
}
