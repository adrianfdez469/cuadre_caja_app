import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/cart_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';
import '../cart_items_screen.dart';
import 'accounts_sheet.dart';
import 'cobrar_button.dart';
import '../cobrar_screen.dart';

/// Barra de cobro fija de la pantalla de venta (Dirección B "Pulgar"): el
/// total nunca se abre, nunca se tapa. "N artículos" abre `CartItemsScreen`,
/// una vista aparte (no una expansión en línea).
class PosCheckoutBar extends StatelessWidget {
  const PosCheckoutBar({super.key});

  Future<void> _cobrar(BuildContext context) async {
    await showCobrarScreen(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cartProvider = context.watch<CartProvider>();
    final monedas = context.watch<MonedasProvider>();
    final activeCart = cartProvider.activeCart;
    final items = activeCart?.items ?? const <CartItemModel>[];
    final total = monedas.cartTotal(items);
    final habilitado = items.isNotEmpty;
    // Unidades reales (no líneas distintas): 3 × un producto son 3 artículos.
    final totalUnidades = activeCart?.unidadesCount ?? 0;
    // Solo el número, para el badge del ícono de carrito.
    final totalUnidadesNumero = totalUnidades == totalUnidades.roundToDouble()
        ? totalUnidades.toInt().toString()
        : totalUnidades.toStringAsFixed(1);
    final totalUnidadesLabel = Formatters.formatUnidades(totalUnidades);
    // Borde resaltado y texto/ícono de mayor contraste que el fondo
    // translúcido anterior, para los 3 controles de esta fila.
    final borderColor = colors.onInverse.withValues(alpha: 0.4);
    final contrastColor = colors.onInverse;

    return Container(
      color: colors.inverse,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: 'Cuenta activa: ${activeCart?.nombre ?? "-"}. Cambiar de cuenta.',
                    child: InkWell(
                      onTap: () => AccountsSheet.show(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppTapTarget.min),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'A cobrar · ${activeCart?.nombre ?? '-'}',
                                    style: TextStyle(fontSize: 11.5, color: contrastColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.expand_more, size: 16, color: contrastColor),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: 'Vaciar carrito',
                    child: TextButton.icon(
                      onPressed: () => confirmClearCart(
                        context,
                        cartProvider,
                        cartProvider.activeCartIndex,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: contrastColor,
                        minimumSize: const Size(0, AppTapTarget.min),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      icon: const Icon(Icons.remove_shopping_cart_outlined, size: 16),
                      label: const Text('Vaciar', style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'Ver el detalle del carrito, $totalUnidadesLabel.',
                  child: InkWell(
                    // Se abre también vacío: ahí viven el menú de la cuenta y
                    // el botón de cerrarla.
                    onTap: () => showCartItemsScreen(context),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: AppTapTarget.min,
                        minHeight: AppTapTarget.min,
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: borderColor),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 18, color: contrastColor),
                              if (totalUnidades > 0)
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                    decoration: BoxDecoration(
                                      color: colors.negative,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: colors.inverse, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        totalUnidadesNumero,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: MultiCurrencyAmount(
                    amount: total,
                    variant: MultiCurrencyVariant.checkout,
                    onInverseSurface: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CobrarButton(
              unidades: totalUnidades,
              onPressed: habilitado ? () => _cobrar(context) : null,
            ),
          ],
        ),
      ),
    );
  }
}
