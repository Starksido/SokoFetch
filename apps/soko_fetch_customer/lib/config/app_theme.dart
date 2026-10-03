import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color brand = Color(0xFF191C1D);
  static const Color accent = Color(0xFFAB3500);
  static const Color primaryContainer = Color(0xFFFF6B35);
  static const Color primaryFixed = Color(0xFFFFDBD0);
  static const Color teal = Color(0xFF006A62);
  static const Color secondaryContainer = Color(0xFF70F8E8);
  static const Color gold = Color(0xFFF5A623);
  static const Color lgray = Color(0xFFF8F9FA);
  static const Color surfaceContainer = Color(0xFFF3F4F5);
  static const Color surfaceHigh = Color(0xFFE7E8E9);
  static const Color outlineVariant = Color(0xFFE1BFB5);
  static const Color mgray = Color(0xFF594139);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: accent,
          secondary: teal,
          surface: Colors.white,
          primaryContainer: primaryContainer,
          secondaryContainer: secondaryContainer,
        ),
        scaffoldBackgroundColor: lgray,
        appBarTheme: const AppBarTheme(
          backgroundColor: lgray,
          foregroundColor: brand,
          elevation: 0,
          centerTitle: false,
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
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 15),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: outlineVariant, width: 0.6),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
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
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: brand),
          headlineMedium: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: brand),
          headlineSmall: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: brand),
          titleLarge: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: brand),
          titleMedium: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: brand),
          bodyLarge: TextStyle(fontFamily: 'Poppins', color: brand),
          bodyMedium: TextStyle(fontFamily: 'Poppins', color: mgray),
          bodySmall: TextStyle(fontFamily: 'Poppins', color: mgray),
        ),
      );
}
