import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color brand = Color(0xFF191C1D);
  static const Color accent = Color(0xFFAB3500);
  static const Color primaryContainer = Color(0xFFFF6B35);
  static const Color primaryFixed = Color(0xFFFFDBD0);
  static const Color teal = Color(0xFF006A62);
  static const Color secondary = teal;
  static const Color secondaryContainer = Color(0xFF70F8E8);
  static const Color red = Color(0xFFBA1A1A);
  static const Color gold = Color(0xFFF5A623);
  static const Color green = Color(0xFF27AE60);
  static const Color lgray = Color(0xFFF8F9FA);
  static const Color surfaceContainer = Color(0xFFF3F4F5);
  static const Color surfaceHigh = Color(0xFFE7E8E9);
  static const Color outlineVariant = Color(0xFFE1BFB5);
  static const Color mgray = Color(0xFF594139);

  static OutlineInputBorder _border([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: side);

  /// Used everywhere except the customer area.
  static ThemeData get light => ThemeData(
        useMaterial3: true,
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
          titleTextStyle: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 22, color: accent),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: outlineVariant, width: 0.6),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceContainer,
          border: _border(),
          enabledBorder: _border(),
          focusedBorder: _border(const BorderSide(color: accent, width: 2)),
        ),
      );

  /// The customer screens were built with full-width buttons and card
  /// margins, so they keep their own variant. Merchant and courier screens
  /// put buttons inside Rows, where a full-width minimum would not lay out.
  static ThemeData get customer {
    final base = light;
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(centerTitle: false),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge:
            const TextStyle(fontWeight: FontWeight.w700, color: brand),
        headlineMedium:
            const TextStyle(fontWeight: FontWeight.w700, color: brand),
        headlineSmall:
            const TextStyle(fontWeight: FontWeight.w700, color: brand),
        titleLarge: const TextStyle(fontWeight: FontWeight.w600, color: brand),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: brand),
        bodyLarge: const TextStyle(color: brand),
        bodyMedium: const TextStyle(color: mgray),
        bodySmall: const TextStyle(color: mgray),
      ),
    );
  }
}
