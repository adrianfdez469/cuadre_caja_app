import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/utils/formatters.dart';
import '../providers/monedas_provider.dart';

enum MultiCurrencyVariant { compact, product, total }

/// Muestra un monto en moneda base con equivalencias en monedas alternativas.
class MultiCurrencyAmount extends StatelessWidget {
  /// Monto ya normalizado a moneda base del negocio.
  final double amount;
  final MultiCurrencyVariant variant;
  final TextAlign textAlign;
  final Color? primaryColor;

  const MultiCurrencyAmount({
    super.key,
    required this.amount,
    this.variant = MultiCurrencyVariant.product,
    this.textAlign = TextAlign.start,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final monedas = context.watch<MonedasProvider>();
    final baseCode = monedas.monedaBase;
    final primaryText = Formatters.formatMonedaAmount(
      amount,
      simbolo: monedas.simboloFor(baseCode),
      code: baseCode,
    );

    final primaryStyle = TextStyle(
      fontSize: switch (variant) {
        MultiCurrencyVariant.total => 24,
        MultiCurrencyVariant.product => 18,
        MultiCurrencyVariant.compact => 14,
      },
      fontWeight: FontWeight.bold,
      color: primaryColor ?? AppColors.primary,
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
          style: TextStyle(
            fontSize: switch (variant) {
              MultiCurrencyVariant.total => 13,
              MultiCurrencyVariant.product => 12,
              MultiCurrencyVariant.compact => 11,
            },
            color: AppColors.textSecondary,
          ),
          textAlign: textAlign,
        ),
      ],
    );
  }
}
