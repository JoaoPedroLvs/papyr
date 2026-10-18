import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/theme.dart';

Color c(int v) => Color(v);
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  test('light scheme uses the brand colors', () {
    final s = papyrTheme(Brightness.light).colorScheme;
    expect(s.surface, c(0xFFF6F3EC));
    expect(s.primary, c(0xFF102E50));
    expect(s.onPrimary, c(0xFFF6F3EC));
    expect(s.primaryContainer, c(0xFF102E50));
    expect(s.surfaceContainerLowest, c(0xFFFFFFFF));
    expect(s.surfaceContainer, c(0xFFEEE9DD));
    expect(s.surfaceContainerHigh, c(0xFFE8E2D4));
    expect(s.outlineVariant, c(0xFFE6E1D6));
    expect(s.onSurfaceVariant, c(0xFF6B655A));
    expect(s.outline, c(0xFF8A8376));
    expect(s.secondary, c(0xFF32B0FA));
    expect(s.tertiary, c(0xFF00FD9A));
    expect(s.error, c(0xFFB3261E));
  });

  test('dark scheme is "tinta à noite"', () {
    final s = papyrTheme(Brightness.dark).colorScheme;
    expect(s.surface, c(0xFF0E1A2A));
    expect(s.primary, c(0xFFF1EEE6));
    expect(s.onPrimary, c(0xFF102E50));
    expect(s.primaryContainer, c(0xFF1F3A5F));
    expect(s.onPrimaryContainer, c(0xFFF6F3EC));
    expect(s.surfaceContainerLowest, c(0xFF16263B));
    expect(s.surfaceContainer, c(0xFF1A2B42));
    expect(s.surfaceContainerHigh, c(0xFF1E3150));
    expect(s.outlineVariant, c(0xFF24364F));
    expect(s.onSurfaceVariant, c(0xFFA3ADBB));
    expect(s.outline, c(0xFF7F8DA3));
    expect(s.error, c(0xFFF2B8B5));
  });

  test('titles use Newsreader at their own optical size; the rest is Outfit', () {
    final t = papyrTheme(Brightness.light);
    void serifAt(TextStyle? s, double size) {
      expect(s!.fontFamily, 'Newsreader');
      expect(s.fontSize, size);
      expect(s.fontWeight, FontWeight.w500);
      expect(s.fontVariations, containsAll([FontVariation('opsz', size), const FontVariation('wght', 500)]));
    }
    serifAt(t.textTheme.headlineLarge, 34);
    serifAt(t.textTheme.headlineMedium, 28);
    serifAt(t.dialogTheme.titleTextStyle, 22);
    // AlertDialog uses this style as-is (it does not merge the ambient color): without a color the title paints white
    expect(t.dialogTheme.titleTextStyle!.color, t.colorScheme.onSurface);
    expect(t.textTheme.bodyMedium!.fontFamily, 'Outfit');
    expect(t.textTheme.titleMedium!.fontWeight, FontWeight.w500);
    expect(t.textTheme.labelLarge!.fontWeight, FontWeight.w600);
  });

  // Review Focus 2
  for (final b in Brightness.values) {
    test('$b text pairs are legible', () {
      final s = papyrTheme(b).colorScheme;
      expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onSurfaceVariant, s.surfaceContainer), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onInverseSurface, s.inverseSurface), greaterThanOrEqualTo(4.5));
      expect(contrast(s.error, s.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(3));
      expect(contrast(Brand.green, s.primaryContainer), greaterThanOrEqualTo(3));
    });
  }
}
