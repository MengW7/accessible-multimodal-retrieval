import 'package:flutter/material.dart';

// Keep Material's sizes, weights and line heights, but avoid Latin tracking
// between Chinese characters. Apply this to every theme, including contrast.
const _chineseTextTheme = TextTheme(
  displayLarge: TextStyle(letterSpacing: 0),
  displayMedium: TextStyle(letterSpacing: 0),
  displaySmall: TextStyle(letterSpacing: 0),
  headlineLarge: TextStyle(letterSpacing: 0),
  headlineMedium: TextStyle(letterSpacing: 0),
  headlineSmall: TextStyle(letterSpacing: 0),
  titleLarge: TextStyle(letterSpacing: 0),
  titleMedium: TextStyle(letterSpacing: 0),
  titleSmall: TextStyle(letterSpacing: 0),
  bodyLarge: TextStyle(letterSpacing: 0),
  bodyMedium: TextStyle(letterSpacing: 0),
  bodySmall: TextStyle(letterSpacing: 0),
  labelLarge: TextStyle(letterSpacing: 0),
  labelMedium: TextStyle(letterSpacing: 0),
  labelSmall: TextStyle(letterSpacing: 0),
);

ThemeData retrievalTheme(Brightness brightness, {bool highContrast = false}) {
  final dark = brightness == Brightness.dark;
  final scheme = highContrast
      ? (dark
                ? const ColorScheme.highContrastDark()
                : const ColorScheme.highContrastLight())
            .copyWith(
              primary: dark ? const Color(0xffffee00) : const Color(0xff0045a0),
              onPrimary: dark ? Colors.black : Colors.white,
              primaryContainer: dark
                  ? const Color(0xffffee00)
                  : const Color(0xff0045a0),
              onPrimaryContainer: dark ? Colors.black : Colors.white,
              surface: dark ? Colors.black : Colors.white,
              onSurface: dark ? Colors.white : Colors.black,
              onSurfaceVariant: dark ? Colors.white : Colors.black,
              surfaceContainerHighest: dark ? Colors.black : Colors.white,
              surfaceContainerHigh: dark ? Colors.black : Colors.white,
              surfaceContainer: dark ? Colors.black : Colors.white,
              surfaceContainerLow: dark ? Colors.black : Colors.white,
              surfaceContainerLowest: dark ? Colors.black : Colors.white,
              outline: dark ? Colors.white : Colors.black,
              outlineVariant: dark ? Colors.white : Colors.black,
              error: dark ? const Color(0xffffb4ab) : const Color(0xff990000),
              onError: dark ? Colors.black : Colors.white,
            )
      : ColorScheme.fromSeed(
          seedColor: const Color(0xff235d58),
          brightness: brightness,
        );
  final disabled = dark ? const Color(0xffb3b3b3) : const Color(0xff595959);
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei',
    fontFamilyFallback: const [
      'Microsoft YaHei UI',
      'PingFang SC',
      'Noto Sans CJK SC',
      'Segoe UI',
    ],
    textTheme: _chineseTextTheme,
    primaryTextTheme: _chineseTextTheme,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    disabledColor: disabled,
    focusColor: scheme.primary.withValues(alpha: .18),
  );
  final minimum = const Size(48, 48);
  final padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  return base.copyWith(
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.primary, width: 3),
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: disabled),
      ),
      labelStyle: TextStyle(color: scheme.onSurface),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minimum,
        padding: padding,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.surface,
        disabledForegroundColor: disabled,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minimum,
        padding: padding,
        foregroundColor: scheme.primary,
        disabledForegroundColor: disabled,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minimum,
        padding: padding,
        foregroundColor: scheme.primary,
        disabledForegroundColor: disabled,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
