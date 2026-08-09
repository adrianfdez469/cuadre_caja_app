import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/cart_model.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';
import '../payment_modal.dart';

/// Barra de total + botón de cobro, compartida por CartScreen y el panel del
/// escáner.
///
/// [onSaleCompleted] se invoca solo si la venta se completó; cada pantalla
/// decide qué hacer entonces (CartScreen vuelve al POS, el escáner se queda).
class CartCheckoutBar extends StatelessWidget {
  const CartCheckoutBar({
    super.key,
    required this.items,
    this.dense = false,
    this.onSaleCompleted,
  });

  final List<CartItemModel> items;

  /// Versión de menos alto para el panel del escáner.
  final bool dense;
  final VoidCallback? onSaleCompleted;

  Future<void> _cobrar(BuildContext context) async {
    final ok = await PaymentModal.show(context);
    if (ok == true && context.mounted) onSaleCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final monedas = context.watch<MonedasProvider>();
    final totalBase = monedas.cartTotal(items);
    final habilitado = items.isNotEmpty;

    final row = Row(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total',
              style: TextStyle(
                fontSize: dense ? 12 : 14,
                color: AppColors.textSecondary,
              ),
            ),
            MultiCurrencyAmount(
              amount: totalBase,
              variant: MultiCurrencyVariant.total,
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          height: dense ? 42 : 50,
          child: ElevatedButton.icon(
            onPressed: habilitado ? () => _cobrar(context) : null,
            icon: const Icon(Icons.payment),
            label: Text(
              'Cobrar',
              style: TextStyle(
                fontSize: dense ? 15 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: dense ? 20 : 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );

    if (dense) {
      // Dentro del panel del escáner: sin sombra ni SafeArea, el panel ya los
      // aporta.
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: row,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(child: row),
    );
  }
}
