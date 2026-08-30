import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/formatters.dart';

/// Hoja "Moneda del pago": cambia la moneda de un bloque de pago ya existente.
/// Cada opción muestra cuánto sería el total en esa moneda, para que el cajero
/// decida sin hacer la cuenta.
class MonedaPagoSheet extends StatelessWidget {
  final List<String> monedas;
  final String seleccionada;

  /// Total de la venta en moneda base, para convertirlo a cada opción.
  final double totalBase;
  final String monedaBase;
  final Map<String, double> tasas;

  const MonedaPagoSheet({
    super.key,
    required this.monedas,
    required this.seleccionada,
    required this.totalBase,
    required this.monedaBase,
    required this.tasas,
  });

  static Future<String?> show(
    BuildContext context, {
    required List<String> monedas,
    required String seleccionada,
    required double totalBase,
    required String monedaBase,
    required Map<String, double> tasas,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MonedaPagoSheet(
        monedas: monedas,
        seleccionada: seleccionada,
        totalBase: totalBase,
        monedaBase: monedaBase,
        tasas: tasas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Moneda del pago',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: monedas.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, thickness: 1, color: colors.border),
              itemBuilder: (context, index) {
                final moneda = monedas[index];
                final equivalente = CurrencyUtils.convertFromBase(
                  totalBase,
                  moneda,
                  tasas,
                  monedaBase,
                );
                return InkWell(
                  onTap: () => Navigator.pop(context, moneda),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          moneda == seleccionada
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 22,
                          color: moneda == seleccionada
                              ? colors.accent
                              : colors.textDisabled,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            moneda,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${Formatters.formatNumber(equivalente)} $moneda',
                          style: tabularNums(
                            TextStyle(fontSize: 14, color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
