import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color brand = Color(0xFF191C1D);
  static const Color accent = Color(0xFFAB3500);
  static const Color primaryContainer = Color(0xFFFF6B35);
  static const Color secondary = Color(0xFF006A62);
  static const Color secondaryContainer = Color(0xFF70F8E8);
  static const Color red = Color(0xFFBA1A1A);
  static const Color gold = Color(0xFFF5A623);
  static const Color lgray = Color(0xFFF8F9FA);
  static const Color surfaceContainer = Color(0xFFF3F4F5);
  static const Color surfaceHigh = Color(0xFFE7E8E9);
  static const Color outlineVariant = Color(0xFFE1BFB5);
  static const Color mgray = Color(0xFF594139);
  static const Color green = Color(0xFF27AE60);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: accent,
          secondary: secondary,
          surface: Colors.white,
          primaryContainer: primaryContainer,
          secondaryContainer: secondaryContainer,
        ),
        scaffoldBackgroundColor: lgray,
        appBarTheme: const AppBarTheme(
          backgroundColor: lgray,
          foregroundColor: brand,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: accent,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: outlineVariant, width: 0.6)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceContainer,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: accent, width: 2)),
        ),
      );
}
