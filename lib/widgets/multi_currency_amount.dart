import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/formatters.dart';
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
    final primaryText = Formatters.formatMonedaAmount(
      amount,
      simbolo: monedas.simboloFor(baseCode),
      code: baseCode,
    );

    final primaryFontSize = switch (variant) {
      MultiCurrencyVariant.checkout => 38.0,
      MultiCurrencyVariant.total => 24.0,
      MultiCurrencyVariant.product => 18.0,
      MultiCurrencyVariant.compact => 14.0,
    };
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

    final alts = monedas.monedasAlternativas;
    if (alts.isEmpty) {
      return Text(primaryText, style: primaryStyle, textAlign: textAlign);
    }

    final altParts = alts.map((m) {
      final converted = monedas.convertFromBase(amount, m.monedaCode);
      return '≈ ${Formatters.formatMonedaAmount(converted, simbolo: m.simbolo, code: m.monedaCode)}';
    }).join(' · ');

    return Column(
      crossAxisAlignment: switch (textAlign) {
        TextAlign.center => CrossAxisAlignment.center,
        TextAlign.end => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      },
      children: [
        Text(primaryText, style: primaryStyle, textAlign: textAlign),
        const SizedBox(height: 2),
        Text(
          altParts,
          style: tabularNums(
            TextStyle(
              fontSize: switch (variant) {
                MultiCurrencyVariant.checkout => 12.5,
                MultiCurrencyVariant.total => 13,
                MultiCurrencyVariant.product => 12,
                MultiCurrencyVariant.compact => 11,
              },
              color: onInverseSurface
                  ? colors.onInverseMuted
                  : colors.textSecondary,
            ),
          ),
          textAlign: textAlign,
        ),
      ],
    );
  }
}
