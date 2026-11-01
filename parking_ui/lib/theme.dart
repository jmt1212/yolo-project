import 'package:flutter/material.dart';

/// Warna wireframe PetraPark (monokrom).
class Pk {
  static const ink = Color(0xFF262626);
  static const muted = Color(0xFF6E6E6E);
  static const faint = Color(0xFF9A9A9A);
  static const line = Color(0xFFDADADA);
  static const fill = Color(0xFFEEEEEE);
  static const dark = Color(0xFF3A3A3A);
  static const page = Colors.white;
  static const error = Color(0xFFB3261E);
}

ThemeData buildTheme() {
  const radius = BorderRadius.all(Radius.circular(4));
  const shape = RoundedRectangleBorder(borderRadius: radius);
  const pad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: Pk.dark,
      onPrimary: Colors.white,
      secondary: Pk.muted,
      surface: Pk.page,
      onSurface: Pk.ink,
      outline: Pk.line,
      error: Pk.error,
    ),
    scaffoldBackgroundColor: Pk.page,
    dividerColor: Pk.line,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Pk.ink, displayColor: Pk.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Pk.page,
      foregroundColor: Pk.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: Pk.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        padding: pad,
        backgroundColor: Pk.dark,
        disabledBackgroundColor: Pk.fill,
        disabledForegroundColor: Pk.faint,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        padding: pad,
        foregroundColor: Pk.ink,
        side: const BorderSide(color: Pk.line),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape, foregroundColor: Pk.ink),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Pk.page,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: Pk.line),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Pk.line),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Pk.fill,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Pk.ink),
  );
}
