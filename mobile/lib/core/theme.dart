import 'package:flutter/material.dart';

abstract final class InspiratTheme {
  static const ink = Color(0xFF172A2D);
  static const petrol = Color(0xFF1E5B57);
  static const champagne = Color(0xFFC8A96B);
  static const terracotta = Color(0xFFB75D4A);
  static const paper = Color(0xFFF8F5EE);
  static const success = Color(0xFF2C6E61);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: petrol,
      brightness: Brightness.light,
      surface: paper,
    ),
    scaffoldBackgroundColor: paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .75),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white.withValues(alpha: .8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );

  static const _darkSurface = Color(0xFF10191A);
  static const _darkCard = Color(0xFF1C2E30);

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: petrol,
      brightness: Brightness.dark,
      surface: _darkSurface,
    ),
    scaffoldBackgroundColor: _darkSurface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: paper,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: _darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
  );
}
