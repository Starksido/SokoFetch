import 'package:flutter/material.dart';

/// Design tokens. Orange-led: Soko Fetch orange for main buttons, selected
/// states and highlights; white background, warm cream panels, near-black
/// text. Status colours only for status.
abstract final class SfColors {
  // Brand: main buttons, selected tabs/chips, progress, focus
  static const brand = Color(0xFFF26B1D);
  static const onBrand = Color(0xFFFFFFFF);

  // Ink (text)
  static const ink = Color(0xFF1A1A1A);
  static const inkMuted = Color(0xFF5E5E5E); // Secondary text
  static const inkFaint = Color(0xFF8C8C8C); // Hints, captions, disabled

  // Surfaces
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFFF4EC); // Warm cream: inputs, chips, panels
  static const surface3 = Color(0xFFF1E4DA); // Dividers, pressed, skeletons
  static const scrim = Color(0x66000000);

  // Orange for fills and badges (= brand). Use [accentStrong] for orange
  // text on white (4.5:1 contrast); [accentSoft] for tinted backgrounds.
  static const accent = brand;
  static const accentStrong = Color(0xFFC2410C);
  static const accentSoft = Color(0xFFFFE8D9);

  // Status
  static const success = Color(0xFF0E8345);
  static const successSoft = Color(0xFFE6F4EC);
  static const warning = Color(0xFFB76E00);
  static const warningSoft = Color(0xFFFFF3DC);
  static const danger = Color(0xFFD32F2F);
  static const dangerSoft = Color(0xFFFDECEC);

  static const rating = Color(0xFFF5A623); // Rating stars only
}

/// 4-pt spacing scale.
abstract final class SfSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16; // Page gutter
  static const double lg = 24; // Between sections
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class SfRadius {
  static const double sm = 8; // Thumbnails
  static const double md = 12; // Cards, images, inputs
  static const double lg = 16; // Sheets
  static const double pill = 999; // Buttons, chips, pills

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Shadows only on floating things: bottom bars, sheets, map overlays.
abstract final class SfShadow {
  static const floating = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const bar = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2)),
  ];
}

/// Width breakpoints (logical pixels).
enum Breakpoint {
  compact, // Phones
  medium, // Large phones in landscape, small tablets
  expanded; // Tablets, desktop

  static Breakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static Breakpoint fromWidth(double width) => width >= 840
      ? Breakpoint.expanded
      : width >= 600
          ? Breakpoint.medium
          : Breakpoint.compact;
}
