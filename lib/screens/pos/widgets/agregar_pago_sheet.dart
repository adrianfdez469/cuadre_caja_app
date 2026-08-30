import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/formatters.dart';

/// Hoja "Agregar forma de pago": añade un segundo (o tercer) bloque de pago en
/// otra moneda. Cada opción dice cuánto haría falta en esa moneda para cubrir
/// lo que queda, y su equivalente en la moneda base.
class AgregarPagoSheet extends StatelessWidget {
  /// Monedas que todavía no están en el pago.
  final List<String> monedas;

  /// Lo que falta por cubrir, en moneda base. Cero o menos si ya está cubierto.
  final double restanteBase;

  /// Total de la venta en moneda base. Es lo que se muestra cuando ya no falta
  /// nada: con el efectivo sembrado en el total exacto —el caso normal— el
  /// restante es cero y todas las opciones salían en 0,00.
  final double totalBase;

  final String monedaBase;
  final Map<String, double> tasas;

  const AgregarPagoSheet({
    super.key,
    required this.monedas,
    required this.restanteBase,
    required this.totalBase,
    required this.monedaBase,
    required this.tasas,
  });

  static Future<String?> show(
    BuildContext context, {
    required List<String> monedas,
    required double restanteBase,
    required double totalBase,
    required String monedaBase,
    required Map<String, double> tasas,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AgregarPagoSheet(
        monedas: monedas,
        restanteBase: restanteBase,
        totalBase: totalBase,
        monedaBase: monedaBase,
        tasas: tasas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Con el total ya cubierto igual se puede añadir otra moneda (el cliente
    // paga parte en otra y se le da más cambio); solo se avisa.
    final cubierto = restanteBase <= 0.0001;
    final base = cubierto ? totalBase : restanteBase;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Agregar forma de pago',
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
                final enMoneda = CurrencyUtils.convertFromBase(
                  base,
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
                        Expanded(
                          child: Text(
                            'Efectivo $moneda',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${Formatters.formatNumber(enMoneda)} $moneda',
                              style: tabularNums(
                                const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '≈ ${Formatters.formatNumber(base)} $monedaBase',
                              style: tabularNums(
                                TextStyle(
                                  fontSize: 11.5,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (cubierto)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.check, size: 16, color: colors.positive),
                  const SizedBox(width: 8),
                  Text(
                    'Ya está cubierto el total',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
