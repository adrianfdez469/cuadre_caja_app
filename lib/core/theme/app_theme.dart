import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Escala tipográfica de `foundations/paleta.html`: h1 40/700 … caption 11.5/400,
/// con `letterSpacing:-0.025em` en tamaños ≥34px.
TextTheme _textTheme(Color primaryText) {
  TextStyle style(double size, FontWeight weight, {double? letterSpacing}) {
    return TextStyle(
      color: primaryText,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }

  return TextTheme(
    displayLarge: style(40, FontWeight.bold, letterSpacing: -1.0), // h1
    displayMedium: style(34, FontWeight.bold, letterSpacing: -0.85), // h2
    displaySmall: style(26, FontWeight.bold), // h3
    headlineLarge: style(22, FontWeight.bold), // h4
    headlineMedium: style(19, FontWeight.bold), // h5
    headlineSmall: style(17, FontWeight.bold), // h6
    titleLarge: style(17, FontWeight.bold),
    titleMedium: style(15, FontWeight.w600),
    titleSmall: style(13, FontWeight.w600),
    bodyLarge: style(15, FontWeight.normal), // body1
    bodyMedium: style(13, FontWeight.normal), // body2
    bodySmall: style(11.5, FontWeight.normal), // caption
    labelLarge: style(15, FontWeight.bold), // botones
    labelMedium: style(13, FontWeight.w600),
    labelSmall: style(11.5, FontWeight.w600),
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required AppSemanticColors colors,
}) {
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    secondary: colors.neutral,
    onSecondary: brightness == Brightness.light ? Colors.white : colors.page,
    error: colors.negative,
    onError: brightness == Brightness.light ? Colors.white : colors.page,
    surface: colors.raised,
    onSurface: colors.textPrimary,
    surfaceContainerHighest: colors.sunken,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.border,
    outlineVariant: colors.borderStrong,
    inverseSurface: colors.inverse,
    onInverseSurface: colors.onInverse,
  );

  final radiusMd = BorderRadius.circular(AppRadius.md);
  final radiusLg = BorderRadius.circular(AppRadius.lg);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.page,
    textTheme: _textTheme(colors.textPrimary),
    extensions: [colors],
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: colors.raised,
      foregroundColor: colors.textPrimary,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: colors.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radiusMd,
        side: BorderSide(color: colors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.raised,
      shape: RoundedRectangleBorder(borderRadius: radiusLg),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.raised,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.sunken,
      border: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.sunken,
      selectedColor: colors.accent,
      labelStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
      secondaryLabelStyle: TextStyle(color: colors.onAccent, fontSize: 13),
      shape: const StadiumBorder(),
      side: BorderSide.none,
    ),
    // Nota: sin `minimumSize` aquí a propósito. Forzarlo globalmente rompe los
    // botones que ya viven dentro de `SizedBox`/`ConstrainedBox` más chicos que
    // 44/56px en pantallas existentes (ej. la barra de cobro "dense" del panel
    // del escáner). Los objetivos táctiles de `AppTapTarget` se aplican
    // explícitamente por widget donde el mock del design system los pide
    // (Fase 3/4), no como default global.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.inverse,
      contentTextStyle: TextStyle(color: colors.onInverse),
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
    ),
    dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
  );
}

final ThemeData appLightTheme = _buildTheme(
  brightness: Brightness.light,
  colors: AppSemanticColors.light,
);

final ThemeData appDarkTheme = _buildTheme(
  brightness: Brightness.dark,
  colors: AppSemanticColors.dark,
);
