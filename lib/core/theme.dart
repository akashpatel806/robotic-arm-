// lib/core/theme.dart
import 'package:flutter/material.dart';

// ── Color seeds ──────────────────────────────────────────────────────────────
const _primarySeed = Color(0xFF00D4FF); // Cyan-electric
const _secondarySeed = Color(0xFF7B2FFF); // Violet

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: _primarySeed,
      brightness: Brightness.dark,
      secondary: _secondarySeed,
    );
    return _build(base);
  }

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: _primarySeed,
      brightness: Brightness.light,
      secondary: _secondarySeed,
    );
    return _build(base);
  }

  static ThemeData _build(ColorScheme cs) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardTheme(
        color: cs.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: cs.primary,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withOpacity(0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        indicatorColor: cs.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outline.withOpacity(0.3),
        thickness: 1,
      ),
    );
  }
}

// ── Gradient helpers ─────────────────────────────────────────────────────────
LinearGradient get electricGradient => const LinearGradient(
  colors: [Color(0xFF00D4FF), Color(0xFF7B2FFF)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// ── Semantic status colors ────────────────────────────────────────────────────
class StatusColors {
  static const connected = Color(0xFF00E676); // Green
  static const disconnected = Color(0xFFFF5252); // Red
  static const connecting = Color(0xFFFFD740); // Amber
  static const scanning = Color(0xFF40C4FF); // Light-blue
  static const warning = Color(0xFFFF6D00); // Orange
}
