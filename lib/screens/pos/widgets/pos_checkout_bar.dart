import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../data/models/cart_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';
import '../cart_items_screen.dart';
import 'accounts_sheet.dart';
import '../payment_modal.dart';

/// Barra de cobro fija de la pantalla de venta (Dirección B "Pulgar"): el
/// total nunca se abre, nunca se tapa. "N artículos" abre `CartItemsScreen`,
/// una vista aparte (no una expansión en línea).
class PosCheckoutBar extends StatelessWidget {
  const PosCheckoutBar({super.key});

  Future<void> _cobrar(BuildContext context) async {
    await PaymentModal.show(context);
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
                  child: InkWell(
                    onTap: () => AccountsSheet.show(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'A cobrar · ${activeCart?.nombre ?? '-'}',
                            style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.expand_more, size: 16, color: colors.onInverseMuted),
                      ],
                    ),
                  ),
                ),
                if (items.isNotEmpty)
                  InkWell(
                    onTap: () => confirmClearCart(
                      context,
                      cartProvider,
                      cartProvider.activeCartIndex,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.remove_shopping_cart_outlined,
                        size: 16,
                        color: colors.onInverseMuted,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: items.isEmpty ? null : () => showCartItemsScreen(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${items.length} ${items.length == 1 ? 'artículo' : 'artículos'}',
                        style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: colors.onInverseMuted),
                    ],
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
            ElevatedButton(
              onPressed: habilitado ? () => _cobrar(context) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
                disabledBackgroundColor: colors.onInverseMuted.withValues(alpha: 0.3),
                minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'Cobrar',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  if (habilitado) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${items.length} ${items.length == 1 ? 'artículo' : 'artículos'}',
                      style: TextStyle(fontSize: 14, color: colors.onAccent.withValues(alpha: 0.7)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
