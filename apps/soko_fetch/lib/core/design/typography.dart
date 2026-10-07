import 'package:flutter/material.dart';

import 'tokens.dart';

/// Inter, bundled in assets/fonts (SIL Open Font License).
const kFontFamily = 'Inter';

/// Bold headings, calm body text. Use these through
/// `Theme.of(context).textTheme` rather than inline font sizes.
TextTheme sfTextTheme() {
  TextStyle style(double size, FontWeight weight, double height,
          {Color color = SfColors.ink, double spacing = 0}) =>
      TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color,
      );

  return TextTheme(
    displaySmall: style(32, FontWeight.w700, 1.2, spacing: -0.5), // Big numbers, hero
    headlineMedium: style(28, FontWeight.w700, 1.2, spacing: -0.4), // Screen titles
    headlineSmall: style(24, FontWeight.w700, 1.25, spacing: -0.3),
    titleLarge: style(20, FontWeight.w700, 1.25, spacing: -0.2), // Section titles
    titleMedium: style(18, FontWeight.w700, 1.3),
    titleSmall: style(16, FontWeight.w600, 1.35), // Card / row titles
    bodyLarge: style(16, FontWeight.w400, 1.45),
    bodyMedium: style(14, FontWeight.w400, 1.45, color: SfColors.inkMuted),
    bodySmall: style(12, FontWeight.w400, 1.4, color: SfColors.inkMuted),
    labelLarge: style(16, FontWeight.w600, 1.25), // Buttons
    labelMedium: style(14, FontWeight.w600, 1.3),
    labelSmall: style(12, FontWeight.w600, 1.3, spacing: 0.2),
  );
}
