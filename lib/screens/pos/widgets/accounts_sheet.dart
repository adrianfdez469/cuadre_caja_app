import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';

/// Diálogo "Cambiar nombre", compartido por `AccountsSheet` y `CartItemsScreen`.
/// Las cuentas se crean sin preguntar el nombre (consecutivo automático); este
/// diálogo solo sirve para renombrar una que ya existe.
void showRenameCartDialog(
  BuildContext context,
  CartProvider cartProvider,
  int index,
) {
  if (index < 0 || index >= cartProvider.cartCount) return;
  final controller =
      TextEditingController(text: cartProvider.carts[index].nombre);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cambiar nombre'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) {
          Navigator.pop(ctx);
          _aplicarNombre(cartProvider, index, controller.text);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            _aplicarNombre(cartProvider, index, controller.text);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

/// Un nombre en blanco dejaría la cuenta sin etiqueta en los chips: se ignora.
void _aplicarNombre(CartProvider cartProvider, int index, String texto) {
  final nombre = texto.trim();
  if (nombre.isEmpty) return;
  cartProvider.renameCart(index, nombre);
}

/// Confirma y vacía el carrito en [index] (compartido por `AccountsSheet` y
/// `CartItemsScreen`).
///
/// Al vaciar se salta a la primera cuenta que aún tenga productos. [alVaciar]
/// solo se llama si no quedó ninguna: ahí ya no hay nada que mirar, así que
/// los sitios abiertos *encima* de la pantalla de venta (el detalle de la
/// cuenta, la hoja de cuentas) lo usan para cerrarse y volver al catálogo.
/// Desde la propia pantalla de venta se omite, porque no hay nada que cerrar.
void confirmClearCart(
  BuildContext context,
  CartProvider cartProvider,
  int index, {
  VoidCallback? alVaciar,
}) {
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
          onPressed: () async {
            Navigator.pop(ctx);
            cartProvider.switchCart(index);
            await cartProvider.clearActiveCart();
            cartProvider.selectFirstNonEmptyCart();
            // Si el salto encontró una cuenta con venta en curso, la vista
            // sigue teniendo algo que mostrar y no se cierra.
            if (cartProvider.activeCart?.isEmpty ?? true) alVaciar?.call();
          },
          child: Text('Vaciar', style: TextStyle(color: context.colors.negative)),
        ),
      ],
    ),
  );
}

/// Confirma y cierra la cuenta en [index] (compartido por `AccountsSheet` y
/// `CartItemsScreen`). Se puede cerrar aunque tenga productos, por eso el
/// diálogo dice cuántos se pierden.
void confirmCloseCart(BuildContext context, CartProvider cartProvider, int index) {
  if (index < 0 || index >= cartProvider.cartCount) return;
  final cart = cartProvider.carts[index];
  final unidades = cart.unidadesCount;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cerrar cuenta'),
      content: Text(
        unidades > 0
            ? '¿Cerrar "${cart.nombre}"?\n'
                'Se perderán sus ${Formatters.formatUnidades(unidades)}.'
            : '¿Cerrar "${cart.nombre}"?',
      ),
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
          child: Text('Cerrar', style: TextStyle(color: context.colors.negative)),
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
                                case 'renombrar':
                                  showRenameCartDialog(context, cartProvider, index);
                                  break;
                                case 'vaciar':
                                  final navigator = Navigator.of(context);
                                  confirmClearCart(
                                    context,
                                    cartProvider,
                                    index,
                                    // Cierra esta hoja: con la cuenta vacía se
                                    // vuelve al catálogo.
                                    alVaciar: () {
                                      if (navigator.canPop()) navigator.pop();
                                    },
                                  );
                                  break;
                                case 'cerrar':
                                  confirmCloseCart(context, cartProvider, index);
                                  break;
                              }
                            },
                            // Misma regla que el menú de la vista ampliada: la
                            // cuenta principal (índice 0) no se renombra ni se
                            // cierra.
                            itemBuilder: (_) => [
                              if (index != 0)
                                const PopupMenuItem(
                                  value: 'renombrar',
                                  child: Text('Cambiar nombre'),
                                ),
                              if (cart.items.isNotEmpty)
                                const PopupMenuItem(
                                  value: 'vaciar',
                                  child: Text('Vaciar carrito'),
                                ),
                              if (index != 0)
                                PopupMenuItem(
                                  value: 'cerrar',
                                  child: Text('Cerrar cuenta',
                                      style: TextStyle(color: colors.negative)),
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
                // Crea con nombre consecutivo y cierra la hoja: el cajero queda
                // en la pantalla de venta con la cuenta nueva ya activa.
                onPressed: () async {
                  await cartProvider.createNextCart();
                  if (context.mounted) Navigator.pop(context);
                },
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
