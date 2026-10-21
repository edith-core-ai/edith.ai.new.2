import 'package:flutter/material.dart';

/// EDITH theme: clean dark UI, the phone's normal system font, and one
/// accent colour used sparingly. The accent can be changed in Settings.
class EdithTheme {
  static const Color background = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF141B24);
  static const Color surfaceHigh = Color(0xFF1B2430);
  static const Color textPrimary = Color(0xFFEAF2F7);
  static const Color textSecondary = Color(0xFF8A9BAA);
  static const Color divider = Color(0xFF222C38);

  static const Color defaultAccent = Color(0xFF2FE0FF);

  /// Colours offered in Settings. All are bright, so dark text on them
  /// stays readable.
  static const List<Color> accentChoices = [
    Color(0xFF2FE0FF), // cyan (default)
    Color(0xFF7C9CFF), // blue
    Color(0xFFB388FF), // violet
    Color(0xFFFF6FB5), // pink
    Color(0xFFFF5C5C), // red
    Color(0xFFFF9F43), // orange
    Color(0xFFFFD84D), // yellow
    Color(0xFF3DDC97), // green
  ];

  /// The live accent colour. The app rebuilds when it changes.
  static final ValueNotifier<Color> accent =
      ValueNotifier<Color>(defaultAccent);

  static void setAccent(Color color) {
    accent.value = color;
  }

  /// Kept under the old name so every screen picks up the chosen accent.
  static Color get electricBlue => accent.value;

  static Color get electricBlueDim {
    final hsl = HSLColor.fromColor(accent.value);
    return hsl
        .withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0))
        .toColor();
  }

  static ThemeData get theme {
    final blue = electricBlue;
    final blueDim = electricBlueDim;
    final base = ThemeData(brightness: Brightness.dark);
    // No custom font: Flutter uses the normal font of the phone.
    final textTheme = base.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: blue,
      colorScheme: ColorScheme.dark(
        primary: blue,
        secondary: blue,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerLowest: background,
        surfaceContainerLow: surface,
        surfaceContainer: surface,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: surfaceHigh,
      ),
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textPrimary,
        iconTheme: const IconThemeData(color: textPrimary),
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: divider,
      dividerTheme: const DividerThemeData(color: divider, space: 1),
      drawerTheme: const DrawerThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: surfaceHigh),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? blue : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? blue.withValues(alpha: 0.35)
              : surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: textSecondary),
        labelStyle: const TextStyle(color: textSecondary),
        floatingLabelStyle: TextStyle(color: blue),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: blueDim),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: background,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: blue,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: divider),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: blue),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
  }
}
