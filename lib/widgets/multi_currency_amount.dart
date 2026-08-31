import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/formatters.dart';
import '../data/models/moneda_model.dart';
import '../providers/monedas_provider.dart';

enum MultiCurrencyVariant { compact, product, total, checkout }

double _primaryFontSize(MultiCurrencyVariant variant) => switch (variant) {
      MultiCurrencyVariant.checkout => 38.0,
      MultiCurrencyVariant.total => 24.0,
      MultiCurrencyVariant.product => 18.0,
      MultiCurrencyVariant.compact => 14.0,
    };

// El código de moneda va en un tamaño fijo bien más chico que el número,
// como en el mock (`.big s`), no como símbolo pegado al monto.
double _codeFontSize(MultiCurrencyVariant variant) => switch (variant) {
      MultiCurrencyVariant.checkout => 15.0,
      MultiCurrencyVariant.total => 12.0,
      MultiCurrencyVariant.product => 11.0,
      MultiCurrencyVariant.compact => 10.0,
    };

double _altFontSize(MultiCurrencyVariant variant) => switch (variant) {
      MultiCurrencyVariant.checkout => 12.5,
      MultiCurrencyVariant.total => 13,
      MultiCurrencyVariant.product => 12,
      MultiCurrencyVariant.compact => 11,
    };

Color _mutedColor(AppSemanticColors colors, bool onInverseSurface) =>
    onInverseSurface ? colors.onInverseMuted : colors.textSecondary;

String _altText(MonedasProvider monedas, double amount, NegocioMonedaModel m) =>
    '≈ ${Formatters.formatNumber(monedas.convertFromBase(amount, m.monedaCode))} ${m.monedaCode}';

/// Muestra un monto en moneda base con equivalencias en monedas alternativas.
class MultiCurrencyAmount extends StatelessWidget {
  /// Monto ya normalizado a moneda base del negocio.
  final double amount;
  final MultiCurrencyVariant variant;
  final TextAlign textAlign;
  final Color? primaryColor;

  /// Cuando es `true`, usa los tokens `onInverse`/`onInverseMuted` (para
  /// mostrarse sobre la barra de cobro negra u otras superficies invertidas).
  final bool onInverseSurface;

  const MultiCurrencyAmount({
    super.key,
    required this.amount,
    this.variant = MultiCurrencyVariant.product,
    this.textAlign = TextAlign.start,
    this.primaryColor,
    this.onInverseSurface = false,
  });

  /// Solo el monto en moneda base, sin las conversiones. Para layouts que
  /// necesitan ubicar el monto y las conversiones en filas distintas (p.ej.
  /// el catálogo de venta, con el monto junto al nombre y las conversiones
  /// junto a la cantidad) en vez de apiladas como hace este widget.
  static Widget primaryOnly(
    BuildContext context, {
    required double amount,
    MultiCurrencyVariant variant = MultiCurrencyVariant.product,
    TextAlign textAlign = TextAlign.start,
    Color? primaryColor,
    bool onInverseSurface = false,
  }) {
    final monedas = context.watch<MonedasProvider>();
    final colors = context.colors;
    final fontSize = _primaryFontSize(variant);
    final style = tabularNums(
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        // Regla del design system: tamaños ≥34px llevan letter-spacing -0.025em.
        letterSpacing: fontSize >= 34 ? fontSize * -0.025 : null,
        color: primaryColor ?? (onInverseSurface ? colors.onInverse : colors.accent),
      ),
    );
    final codeStyle = tabularNums(
      TextStyle(
        fontSize: _codeFontSize(variant),
        fontWeight: FontWeight.w500,
        color: _mutedColor(colors, onInverseSurface),
      ),
    );
    return Text.rich(
      TextSpan(
        text: Formatters.formatNumber(amount),
        style: style,
        children: [TextSpan(text: ' ${monedas.monedaBase}', style: codeStyle)],
      ),
      textAlign: textAlign,
    );
  }

  /// Solo la línea de conversiones a monedas alternativas, en una sola línea
  /// que se recorta con "…" si no entra; `null` si el negocio no tiene
  /// monedas alternativas configuradas. Mismo caso de uso que [primaryOnly].
  static Widget? alternativesOnly(
    BuildContext context, {
    required double amount,
    MultiCurrencyVariant variant = MultiCurrencyVariant.product,
    TextAlign textAlign = TextAlign.start,
    bool onInverseSurface = false,
  }) {
    final monedas = context.watch<MonedasProvider>();
    final alts = monedas.monedasAlternativas;
    if (alts.isEmpty) return null;
    final colors = context.colors;
    final style = tabularNums(
      TextStyle(
        fontSize: _altFontSize(variant),
        color: _mutedColor(colors, onInverseSurface),
      ),
    );
    return Text(
      alts.map((m) => _altText(monedas, amount, m)).join(' · '),
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Las conversiones a monedas alternativas, una por línea y completas (sin
  /// recortar), en vez de una sola línea unida como [alternativesOnly]. Para
  /// layouts que apilan cada conversión bajo el monto principal (p.ej. el
  /// catálogo de venta). Lista vacía si no hay monedas alternativas.
  static List<Widget> alternativeLines(
    BuildContext context, {
    required double amount,
    MultiCurrencyVariant variant = MultiCurrencyVariant.product,
    TextAlign textAlign = TextAlign.start,
    bool onInverseSurface = false,
  }) {
    final monedas = context.watch<MonedasProvider>();
    final alts = monedas.monedasAlternativas;
    if (alts.isEmpty) return const [];
    final colors = context.colors;
    final style = tabularNums(
      TextStyle(
        fontSize: _altFontSize(variant),
        color: _mutedColor(colors, onInverseSurface),
      ),
    );
    return [
      for (final m in alts)
        Text(
          _altText(monedas, amount, m),
          style: style,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final monedas = context.watch<MonedasProvider>();
    final colors = context.colors;

    final primaryWidget = primaryOnly(
      context,
      amount: amount,
      variant: variant,
      textAlign: textAlign,
      primaryColor: primaryColor,
      onInverseSurface: onInverseSurface,
    );

    final alts = monedas.monedasAlternativas;
    if (alts.isEmpty) {
      return primaryWidget;
    }

    final altStyle = tabularNums(
      TextStyle(
        fontSize: _altFontSize(variant),
        color: _mutedColor(colors, onInverseSurface),
      ),
    );

    // En la barra de cobro (variante `checkout`) cada moneda alternativa va
    // en su propia línea a la derecha del monto: la barra queda más baja al
    // no apilar el total y las conversiones, y con varias monedas una sola
    // línea unida con " · " no entra. Las demás variantes (usadas en
    // encabezados de altura fija, como el panel del escáner) mantienen una
    // sola línea unida, ya con abreviatura en vez de símbolo.
    if (variant == MultiCurrencyVariant.checkout) {
      return Row(
        // Por línea de base, no por el borde inferior de las cajas: con 38px de
        // un lado y 12.5px del otro, alinear los fondos deja los números
        // visiblemente desfasados.
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        // Las conversiones toman su ancho natural y el monto se queda con todo
        // el resto: antes ambos eran flexibles, se repartían el espacio libre a
        // mitades y el total se dibujaba a la mitad de su tamaño aunque al lado
        // sobrara sitio. El hueco que quede va entre los dos, así que el monto
        // sigue pegado al borde izquierdo y las conversiones al derecho.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Se encoge antes que desbordar, y sin recortarse con puntos
          // suspensivos: un importe a medias es peor que un importe pequeño.
          // Ya solo ocurre con totales enormes; mientras no se encoja, su base
          // coincide exactamente con la de la última conversión (al encogerse,
          // `FittedBox` publica la base sin escalar y se desvía unos píxeles:
          // mal menor frente a no ver el total entero).
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: primaryWidget,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            // Las conversiones se apilan hacia arriba desde la última, que es
            // la que comparte línea de base con el monto: un `Column` publica
            // como base la de su primer hijo, así que invertir la lista y
            // crecer hacia arriba deja abajo —y como referencia— a la última.
            verticalDirection: VerticalDirection.up,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in alts.reversed)
                Text(
                  _altText(monedas, amount, m),
                  style: altStyle,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: switch (textAlign) {
        TextAlign.center => CrossAxisAlignment.center,
        TextAlign.end => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      },
      children: [
        primaryWidget,
        const SizedBox(height: 2),
        alternativesOnly(
          context,
          amount: amount,
          variant: variant,
          textAlign: textAlign,
          onInverseSurface: onInverseSurface,
        )!,
      ],
    );
  }
}
