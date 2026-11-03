import 'package:flutter/material.dart';

/// Uygulama renk paleti (lacivert zemin, amber vurgu).
const navy = Color(0xFF14203A);
const navyLight = Color(0xFF1F2E4F);
const navyLine = Color(0xFF33436A);
const amber = Color(0xFFFDB813);
const success = Color(0xFF34D399);
const warning = Color(0xFFFB923C);
const muted = Color(0xFFA3B0CC);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: amber,
    brightness: Brightness.dark,
    primary: amber,
    onPrimary: navy,
    surface: navy,
    surfaceContainerHighest: navyLight,
    error: warning,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: navy,
    appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: navyLight,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: navy,
      labelStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: navyLine)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: navyLine)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: amber)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: amber,
        foregroundColor: navy,
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: navyLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
