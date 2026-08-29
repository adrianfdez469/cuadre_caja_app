import 'package:flutter/material.dart';

/// Radios de esquina del design system (`foundations/paleta.html`).
class AppRadius {
  const AppRadius._();

  static const double sm = 10; // teclas, atajos
  static const double md = 12; // botones, campos, tarjetas
  static const double lg = 16; // diálogos, hojas (bottom sheets)
  static const double pill = 999; // cuentas, categorías
}

/// Objetivos táctiles mínimos del design system (`foundations/paleta.html`).
class AppTapTarget {
  const AppTapTarget._();

  static const double min = 44; // "+", "✕", íconos
  static const double comfortable = 56; // buscador, escáner, botón cobrar
  static const double row = 56; // fila de ajuste / forma de pago
  static const double rowLarge = 72; // fila de catálogo
}

/// Puntos de quiebre de layout responsive.
class AppBreakpoints {
  const AppBreakpoints._();

  /// A partir de este ancho (dp) se considera tablet: la pantalla de venta
  /// pasa de una columna a catálogo + panel de carrito fijo (400dp). Se usa
  /// el umbral "expanded" de Material (no el "medium" de 600) porque el panel
  /// no se angosta: con un ancho menor el catálogo queda demasiado recortado.
  static const double tablet = 840;
}

/// Aplica `tabular-nums` a un [TextStyle], para cifras de importes y cantidades.
TextStyle tabularNums(TextStyle style) {
  return style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Los 6 tonos semánticos de `foundations/paleta.html` (ink = sólido, wash =
/// superficie tenue), más las superficies y colores de texto del sistema.
///
/// Un significado por tono:
/// - [accent]: acción y selección (botón primario, foco, "Cobrar").
/// - [positive]: entra / cubre / salió bien (vuelto, venta cobrada).
/// - [negative]: falta / se agotó / falló (stock 0, sync caída).
/// - [caution]: todavía no es problema (stock bajo, offline).
/// - [info]: se movió sin ganar ni perder (traspaso, sincronizando).
/// - [neutral]: ni bueno ni malo (totales sin signo, controles apagados).
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.accent,
    required this.accentWash,
    required this.onAccent,
    required this.positive,
    required this.positiveWash,
    required this.negative,
    required this.negativeWash,
    required this.caution,
    required this.cautionWash,
    required this.info,
    required this.infoWash,
    required this.neutral,
    required this.neutralWash,
    required this.page,
    required this.raised,
    required this.sunken,
    required this.border,
    required this.borderStrong,
    required this.inverse,
    required this.onInverse,
    required this.onInverseMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
  });

  final Color accent;
  final Color accentWash;
  /// Texto/ícono sobre [accent]: blanco en claro, casi negro en oscuro (el
  /// ámbar del Tablero C es demasiado claro para texto blanco encima).
  final Color onAccent;
  final Color positive;
  final Color positiveWash;
  final Color negative;
  final Color negativeWash;
  final Color caution;
  final Color cautionWash;
  final Color info;
  final Color infoWash;
  final Color neutral;
  final Color neutralWash;

  final Color page;
  final Color raised;
  final Color sunken;
  final Color border;
  final Color borderStrong;

  /// Fondo invertido (barra de cobro, drawer de navegación).
  final Color inverse;
  final Color onInverse;
  final Color onInverseMuted;

  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  static const light = AppSemanticColors(
    accent: Color(0xFF5B4CA8),
    accentWash: Color(0xFFF4F2FB),
    onAccent: Color(0xFFFFFFFF),
    positive: Color(0xFF1F6B3F),
    positiveWash: Color(0xFFF1F7F3),
    negative: Color(0xFFA5382A),
    negativeWash: Color(0xFFFBF3F1),
    caution: Color(0xFF8A5A12),
    cautionWash: Color(0xFFFAF3E9),
    info: Color(0xFF1C5E80),
    infoWash: Color(0xFFEDF4F8),
    neutral: Color(0xFF5B5A63),
    neutralWash: Color(0xFFF3F2F6),
    page: Color(0xFFF7F7FA),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFF3F2F6),
    border: Color(0xFFECEBEF),
    borderStrong: Color(0xFFD8D7DE),
    inverse: Color(0xFF131417),
    onInverse: Color(0xFFFFFFFF),
    onInverseMuted: Color(0xFF9A99A3),
    textPrimary: Color(0xFF131417),
    textSecondary: Color(0xFF5F5E68),
    textDisabled: Color(0xFF9B9AA3),
  );

  /// Modo oscuro: superficies alineadas a `foundations/paleta.html` del
  /// Design System 4, con el morado de marca de la Dirección B como acento
  /// (no el ámbar del Tablero C original) — mismo look en claro y oscuro,
  /// solo cambia el fondo. `inverse`/`onInverse` (la barra de cobro) son un
  /// panel oscuro con texto claro, como en claro.
  static const dark = AppSemanticColors(
    accent: Color(0xFFA493E8),
    accentWash: Color(0xFF241E38),
    onAccent: Color(0xFFFFFFFF),
    positive: Color(0xFF5FB37E),
    positiveWash: Color(0xFF17281D),
    negative: Color(0xFFE08376),
    negativeWash: Color(0xFF2E1D1A),
    caution: Color(0xFFCFA24A),
    cautionWash: Color(0xFF2C2413),
    info: Color(0xFF5FA6CC),
    infoWash: Color(0xFF16242C),
    neutral: Color(0xFFA2A1AB),
    neutralWash: Color(0xFF232329),
    page: Color(0xFF141517),
    raised: Color(0xFF1C1E20),
    sunken: Color(0xFF111214),
    border: Color(0xFF2A2C2F),
    borderStrong: Color(0xFF3A3D43),
    inverse: Color(0xFF17191C),
    onInverse: Color(0xFFF0EFEC),
    onInverseMuted: Color(0xFF8D9096),
    textPrimary: Color(0xFFE9E8E5),
    textSecondary: Color(0xFF8D9096),
    textDisabled: Color(0xFF7E8188),
  );

  @override
  AppSemanticColors copyWith({
    Color? accent,
    Color? accentWash,
    Color? onAccent,
    Color? positive,
    Color? positiveWash,
    Color? negative,
    Color? negativeWash,
    Color? caution,
    Color? cautionWash,
    Color? info,
    Color? infoWash,
    Color? neutral,
    Color? neutralWash,
    Color? page,
    Color? raised,
    Color? sunken,
    Color? border,
    Color? borderStrong,
    Color? inverse,
    Color? onInverse,
    Color? onInverseMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
  }) {
    return AppSemanticColors(
      accent: accent ?? this.accent,
      accentWash: accentWash ?? this.accentWash,
      onAccent: onAccent ?? this.onAccent,
      positive: positive ?? this.positive,
      positiveWash: positiveWash ?? this.positiveWash,
      negative: negative ?? this.negative,
      negativeWash: negativeWash ?? this.negativeWash,
      caution: caution ?? this.caution,
      cautionWash: cautionWash ?? this.cautionWash,
      info: info ?? this.info,
      infoWash: infoWash ?? this.infoWash,
      neutral: neutral ?? this.neutral,
      neutralWash: neutralWash ?? this.neutralWash,
      page: page ?? this.page,
      raised: raised ?? this.raised,
      sunken: sunken ?? this.sunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      inverse: inverse ?? this.inverse,
      onInverse: onInverse ?? this.onInverse,
      onInverseMuted: onInverseMuted ?? this.onInverseMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      positiveWash: Color.lerp(positiveWash, other.positiveWash, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      negativeWash: Color.lerp(negativeWash, other.negativeWash, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      cautionWash: Color.lerp(cautionWash, other.cautionWash, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoWash: Color.lerp(infoWash, other.infoWash, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralWash: Color.lerp(neutralWash, other.neutralWash, t)!,
      page: Color.lerp(page, other.page, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      sunken: Color.lerp(sunken, other.sunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      inverse: Color.lerp(inverse, other.inverse, t)!,
      onInverse: Color.lerp(onInverse, other.onInverse, t)!,
      onInverseMuted: Color.lerp(onInverseMuted, other.onInverseMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  /// Acceso corto a los tokens semánticos del tema activo.
  AppSemanticColors get colors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}
