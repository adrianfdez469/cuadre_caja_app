import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/formatters.dart';
import '../data/models/moneda_model.dart';
import '../providers/monedas_provider.dart';

enum MultiCurrencyVariant { compact, product, total, checkout }

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

  @override
  Widget build(BuildContext context) {
    final monedas = context.watch<MonedasProvider>();
    final colors = context.colors;
    final baseCode = monedas.monedaBase;

    final primaryFontSize = switch (variant) {
      MultiCurrencyVariant.checkout => 38.0,
      MultiCurrencyVariant.total => 24.0,
      MultiCurrencyVariant.product => 18.0,
      MultiCurrencyVariant.compact => 14.0,
    };
    // El código de moneda va en un tamaño fijo bien más chico que el número,
    // como en el mock (`.big s`), no como símbolo pegado al monto.
    final codeFontSize = switch (variant) {
      MultiCurrencyVariant.checkout => 15.0,
      MultiCurrencyVariant.total => 12.0,
      MultiCurrencyVariant.product => 11.0,
      MultiCurrencyVariant.compact => 10.0,
    };
    final mutedColor = onInverseSurface ? colors.onInverseMuted : colors.textSecondary;
    final primaryStyle = tabularNums(
      TextStyle(
        fontSize: primaryFontSize,
        fontWeight: FontWeight.bold,
        // Regla del design system: tamaños ≥34px llevan letter-spacing -0.025em.
        letterSpacing: primaryFontSize >= 34 ? primaryFontSize * -0.025 : null,
        color: primaryColor ??
            (onInverseSurface ? colors.onInverse : colors.accent),
      ),
    );
    final codeStyle = tabularNums(
      TextStyle(fontSize: codeFontSize, fontWeight: FontWeight.w500, color: mutedColor),
    );

    final primaryWidget = Text.rich(
      TextSpan(
        text: Formatters.formatNumber(amount),
        style: primaryStyle,
        children: [TextSpan(text: ' $baseCode', style: codeStyle)],
      ),
      textAlign: textAlign,
    );

    final alts = monedas.monedasAlternativas;
    if (alts.isEmpty) {
      return primaryWidget;
    }

    final altStyle = tabularNums(
      TextStyle(
        fontSize: switch (variant) {
          MultiCurrencyVariant.checkout => 12.5,
          MultiCurrencyVariant.total => 13,
          MultiCurrencyVariant.product => 12,
          MultiCurrencyVariant.compact => 11,
        },
        color: mutedColor,
      ),
    );

    String altText(NegocioMonedaModel m) =>
        '≈ ${Formatters.formatNumber(monedas.convertFromBase(amount, m.monedaCode))} ${m.monedaCode}';

    // En la barra de cobro (variante `checkout`) cada moneda alternativa va
    // en su propia línea a la derecha del monto: la barra queda más baja al
    // no apilar el total y las conversiones, y con varias monedas una sola
    // línea unida con " · " no entra. Las demás variantes (usadas en
    // encabezados de altura fija, como el panel del escáner) mantienen una
    // sola línea unida, ya con abreviatura en vez de símbolo.
    if (variant == MultiCurrencyVariant.checkout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          primaryWidget,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in alts)
                  Text(
                    altText(m),
                    style: altStyle,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
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
        Text(
          alts.map(altText).join(' · '),
          style: altStyle,
          textAlign: textAlign,
        ),
      ],
    );
  }
}
