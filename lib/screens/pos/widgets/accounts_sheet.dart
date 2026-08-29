import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';

/// Diálogo "Nueva cuenta", compartido por `AccountsSheet` y `CartItemsScreen`
/// (los chips de cuenta de ambas vistas crean cuentas de la misma forma).
void showCreateCartDialog(BuildContext context, CartProvider cartProvider) {
  final controller =
      TextEditingController(text: 'Carrito ${cartProvider.cartCount + 1}');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nueva cuenta'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            cartProvider.createCart(controller.text);
          },
          child: const Text('Crear'),
        ),
      ],
    ),
  );
}

/// Confirma y vacía el carrito en [index] (compartido por `AccountsSheet` y
/// `CartItemsScreen`).
void confirmClearCart(BuildContext context, CartProvider cartProvider, int index) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Vaciar carrito'),
      content: const Text('¿Eliminar todos los productos de esta cuenta?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            cartProvider.switchCart(index);
            cartProvider.clearActiveCart();
          },
          child: Text('Vaciar', style: TextStyle(color: context.colors.negative)),
        ),
      ],
    ),
  );
}

/// Confirma y elimina la cuenta en [index] (compartido por `AccountsSheet` y
/// `CartItemsScreen`).
void confirmDeleteCart(BuildContext context, CartProvider cartProvider, int index) {
  final nombre = cartProvider.carts[index].nombre;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar cuenta'),
      content: Text('¿Eliminar "$nombre"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            cartProvider.deleteCart(index);
          },
          child: Text('Eliminar', style: TextStyle(color: context.colors.negative)),
        ),
      ],
    ),
  );
}

/// Hoja "Cuentas abiertas": cambiar de carrito activo, crear uno nuevo,
/// vaciar o eliminar uno vacío. Reemplaza el menú y los diálogos que antes
/// vivían en la pantalla de carrito a pantalla completa, según
/// `pos-mobile-estados.html` (Estado 2).
class AccountsSheet {
  AccountsSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AccountsSheetContent(),
    );
  }
}

class _AccountsSheetContent extends StatelessWidget {
  const _AccountsSheetContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cartProvider = context.watch<CartProvider>();
    final monedas = context.watch<MonedasProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cuentas abiertas',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cartProvider.cartCount,
                itemBuilder: (context, index) {
                  final cart = cartProvider.carts[index];
                  final isActive = index == cartProvider.activeCartIndex;
                  return InkWell(
                    onTap: () {
                      cartProvider.switchCart(index);
                      Navigator.pop(context);
                    },
                    child: Container(
                      color: isActive ? colors.accentWash : null,
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isActive ? colors.accent : colors.sunken,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            alignment: Alignment.center,
                            child: isActive
                                ? Icon(Icons.check, color: colors.onAccent, size: 20)
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  cart.nombre,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  Formatters.formatUnidades(cart.unidadesCount),
                                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (cart.items.isNotEmpty)
                            MultiCurrencyAmount(
                              amount: monedas.cartTotal(cart.items),
                              variant: MultiCurrencyVariant.compact,
                              textAlign: TextAlign.end,
                            ),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_horiz, color: colors.textSecondary),
                            onSelected: (value) {
                              switch (value) {
                                case 'vaciar':
                                  confirmClearCart(context, cartProvider, index);
                                  break;
                                case 'eliminar':
                                  confirmDeleteCart(context, cartProvider, index);
                                  break;
                              }
                            },
                            itemBuilder: (_) => [
                              if (cart.items.isNotEmpty)
                                const PopupMenuItem(
                                  value: 'vaciar',
                                  child: Text('Vaciar carrito'),
                                ),
                              if (cart.isEmpty && cartProvider.cartCount > 1)
                                PopupMenuItem(
                                  value: 'eliminar',
                                  child: Text('Eliminar', style: TextStyle(color: colors.negative)),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: () => showCreateCartDialog(context, cartProvider),
                icon: const Icon(Icons.add),
                label: const Text('Nueva cuenta'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
