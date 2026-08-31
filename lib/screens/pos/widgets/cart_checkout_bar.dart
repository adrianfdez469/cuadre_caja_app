import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/models/cart_model.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';
import '../cobrar_screen.dart';

/// Barra de total + botón de cobro del panel del escáner (bottom sheet sobre
/// la cámara). La pantalla de venta usa su propia `PosCheckoutBar`, fija y
/// con líneas de carrito plegables.
///
/// [onSaleCompleted] se invoca solo si la venta se completó.
class CartCheckoutBar extends StatelessWidget {
  const CartCheckoutBar({
    super.key,
    required this.items,
    this.onSaleCompleted,
  });

  final List<CartItemModel> items;
  final VoidCallback? onSaleCompleted;

  Future<void> _cobrar(BuildContext context) async {
    final res = await showCobrarScreen(context);
    if (res == CobrarResult.vendida && context.mounted) onSaleCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final monedas = context.watch<MonedasProvider>();
    final colors = context.colors;
    final totalBase = monedas.cartTotal(items);
    final habilitado = items.isNotEmpty;

    // Dentro del panel del escáner: sin sombra ni SafeArea, el panel ya los aporta.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          // `Expanded` en vez de un `Column` suelto + `Spacer`: con la letra
          // ampliada el total y sus conversiones no cabían y desbordaban la
          // barra. Así el bloque cede el ancho que le sobra al botón.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                MultiCurrencyAmount(
                  amount: totalBase,
                  variant: MultiCurrencyVariant.total,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: AppTapTarget.min,
            child: ElevatedButton.icon(
              onPressed: habilitado ? () => _cobrar(context) : null,
              icon: const Icon(Icons.payment),
              label: const Text(
                'Cobrar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
