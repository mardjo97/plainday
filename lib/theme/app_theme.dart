import 'package:flutter/material.dart';

abstract final class PlaindayTheme {
  static const seed = Color(0xFF2F6F5E);
  static const surface = Color(0xFFF2F4F3);
  static const ink = Color(0xFF1C1F1E);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Georgia',
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: ink,
          letterSpacing: -0.5,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: 'Georgia',
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.35),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
