import 'package:flutter/material.dart';

import 'design/tokens.dart';
import 'design/typography.dart';

export 'design/tokens.dart';
export 'design/typography.dart';

class AppTheme {
  AppTheme._();

  static WidgetStateProperty<T> _byState<T>(T selected, T other) =>
      WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? selected : other);

  static ThemeData get light {
    final text = sfTextTheme();
    const scheme = ColorScheme.light(
      primary: SfColors.brand,
      onPrimary: SfColors.onBrand,
      secondary: SfColors.accentStrong,
      onSecondary: SfColors.onBrand,
      tertiary: SfColors.success,
      surface: SfColors.surface,
      onSurface: SfColors.ink,
      onSurfaceVariant: SfColors.inkMuted,
      surfaceContainerHighest: SfColors.surface2,
      surfaceContainerHigh: SfColors.surface2,
      surfaceContainer: SfColors.surface2,
      surfaceContainerLow: SfColors.surface,
      outline: SfColors.surface3,
      outlineVariant: SfColors.surface3,
      error: SfColors.danger,
      surfaceTint: Colors.transparent,
    );
    const pill = StadiumBorder();
    const inputBorder = OutlineInputBorder(
        borderRadius: SfRadius.mdAll, borderSide: BorderSide.none);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: kFontFamily,
      textTheme: text,
      scaffoldBackgroundColor: SfColors.surface,
      iconTheme: const IconThemeData(color: SfColors.ink),
      dividerTheme: const DividerThemeData(
          color: SfColors.surface3, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: SfColors.surface,
        foregroundColor: SfColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SfColors.brand,
          foregroundColor: SfColors.onBrand,
          disabledBackgroundColor: SfColors.surface3,
          disabledForegroundColor: SfColors.inkFaint,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: SfSpace.lg),
          shape: pill,
          elevation: 0,
          textStyle: text.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SfColors.surface2,
          foregroundColor: SfColors.ink,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: SfSpace.lg),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SfColors.accentStrong,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: SfSpace.lg),
          side: const BorderSide(color: SfColors.brand),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SfColors.accentStrong,
          shape: pill,
          textStyle: text.labelMedium,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: SfColors.brand,
        foregroundColor: SfColors.onBrand,
        elevation: 2,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SfColors.surface2,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: SfSpace.md, vertical: SfSpace.md),
        hintStyle: text.bodyLarge!.copyWith(color: SfColors.inkFaint),
        labelStyle: text.bodyLarge!.copyWith(color: SfColors.inkMuted),
        floatingLabelStyle: text.bodyMedium!.copyWith(color: SfColors.ink),
        prefixIconColor: SfColors.inkMuted,
        suffixIconColor: SfColors.inkMuted,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: SfColors.brand, width: 2)),
        errorBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: SfColors.danger)),
        focusedErrorBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: SfColors.danger, width: 2)),
      ),
      cardTheme: const CardThemeData(
        color: SfColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: SfRadius.mdAll,
          side: BorderSide(color: SfColors.surface3),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SfColors.surface2,
        selectedColor: SfColors.brand,
        disabledColor: SfColors.surface2,
        side: BorderSide.none,
        shape: pill,
        showCheckmark: false,
        labelStyle: text.labelMedium!.copyWith(
          color: WidgetStateColor.resolveWith((s) =>
              s.contains(WidgetState.selected) ? SfColors.onBrand : SfColors.ink),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: SfSpace.sm, vertical: SfSpace.xs),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SfColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        iconTheme: _byState(
          const IconThemeData(color: SfColors.brand, size: 26),
          const IconThemeData(color: SfColors.inkFaint, size: 26),
        ),
        labelTextStyle: _byState(
          text.labelSmall!.copyWith(color: SfColors.brand),
          text.labelSmall!.copyWith(
              color: SfColors.inkFaint, fontWeight: FontWeight.w500),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: SfColors.surface,
        indicatorColor: SfColors.accentSoft,
        selectedIconTheme: const IconThemeData(color: SfColors.brand),
        unselectedIconTheme: const IconThemeData(color: SfColors.inkFaint),
        selectedLabelTextStyle: text.labelSmall!.copyWith(color: SfColors.brand),
        unselectedLabelTextStyle:
            text.labelSmall!.copyWith(color: SfColors.inkFaint),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: SfColors.ink,
        unselectedLabelColor: SfColors.inkFaint,
        labelStyle: text.labelMedium,
        unselectedLabelStyle: text.labelMedium,
        indicatorColor: SfColors.brand,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: SfColors.surface3,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SfColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: SfColors.surface3,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(SfRadius.lg))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SfColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: SfRadius.lgAll),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SfColors.ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: SfRadius.mdAll),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: _byState(SfColors.brand, SfColors.surface3),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: _byState(SfColors.brand, Colors.transparent),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4))),
      ),
      radioTheme: RadioThemeData(
          fillColor: _byState(SfColors.brand, SfColors.inkFaint)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SfColors.brand,
        linearTrackColor: SfColors.surface3,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: SfColors.ink,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
      ),
    );
  }
}
