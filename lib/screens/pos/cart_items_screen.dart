import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../data/models/cart_model.dart';
import '../../data/models/producto_model.dart';
import '../../providers/cart_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/sync_provider.dart';
import '../../widgets/hardware_scanner_listener.dart';
import '../../widgets/multi_currency_amount.dart';
import 'payment_modal.dart';
import 'widgets/accounts_sheet.dart';

/// Abre [CartItemsScreen] con una transición de derecha a izquierda (como un
/// panel que entra desde el borde), en vez del `Navigator.push` con la
/// animación por defecto de la plataforma.
Future<void> showCartItemsScreen(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const CartItemsScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    ),
  );
}

/// Vista "En la venta": el carrito de la cuenta activa a pantalla completa,
/// con los chips de cuenta arriba (cambiar/crear) y el mismo pie de cobro que
/// la pantalla de venta. Se abre desde "N artículos" en la barra de cobro.
class CartItemsScreen extends StatelessWidget {
  const CartItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // La pistola sigue activa acá: el carrito está a la vista y la línea
    // escaneada se agrega arriba de la lista, así que el escaneo se ve. El
    // listener de la pantalla de venta queda inactivo solo mientras esta ruta
    // esté al frente, de modo que siempre hay exactamente uno escuchando.
    return HardwareScannerListener(
      enabled: context.watch<PeriodoProvider>().hasActivePeriodo,
      child: Scaffold(
        body: SafeArea(
          child: CartPanel(onClose: () => Navigator.pop(context)),
        ),
      ),
    );
  }
}

/// Contenido del carrito de la cuenta activa: chips de cuenta, lista de
/// líneas y el pie de cobro. Lo usa [CartItemsScreen] (pantalla completa, con
/// botón de cerrar) y el panel lateral fijo de la pantalla de venta en
/// tablets (sin botón de cerrar, ya que no es una ruta que se pueda cerrar).
class CartPanel extends StatelessWidget {
  /// `null` oculta el botón de cerrar (uso como panel fijo, no como ruta).
  final VoidCallback? onClose;

  const CartPanel({super.key, this.onClose});

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
    final totalUnidadesLabel =
        Formatters.formatUnidades(activeCart?.unidadesCount ?? 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: cartProvider.cartCount + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == cartProvider.cartCount) {
                        return _AddAccountButton(
                          onTap: () =>
                              showCreateCartDialog(context, cartProvider),
                        );
                      }
                      final cart = cartProvider.carts[index];
                      final isActive = index == cartProvider.activeCartIndex;
                      return _AccountChip(
                        label: cart.nombre,
                        selected: isActive,
                        onTap: () => cartProvider.switchCart(index),
                      );
                    },
                  ),
                ),
              ),
              if (activeCart != null &&
                  (activeCart.items.isNotEmpty ||
                      (activeCart.isEmpty && cartProvider.cartCount > 1)))
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: colors.textSecondary),
                  onSelected: (value) {
                    final index = cartProvider.activeCartIndex;
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
                    if (activeCart.items.isNotEmpty)
                      const PopupMenuItem(
                        value: 'vaciar',
                        child: Text('Vaciar carrito'),
                      ),
                    if (activeCart.isEmpty && cartProvider.cartCount > 1)
                      PopupMenuItem(
                        value: 'eliminar',
                        child: Text('Eliminar carrito', style: TextStyle(color: colors.negative)),
                      ),
                  ],
                ),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EN LA VENTA · ${items.length} ${items.length == 1 ? 'ARTÍCULO' : 'ARTÍCULOS'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'El carrito está vacío',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _CartLine(item: items[index]),
                    ),
            ),
            Container(
              color: colors.inverse,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'A cobrar · ${activeCart?.nombre ?? '-'}',
                            style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          totalUnidadesLabel,
                          style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    MultiCurrencyAmount(
                      amount: total,
                      variant: MultiCurrencyVariant.checkout,
                      onInverseSurface: true,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: habilitado ? () => PaymentModal.show(context) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.onAccent,
                        disabledBackgroundColor: colors.onInverseMuted.withValues(alpha: 0.3),
                        minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(
                        habilitado ? 'Cobrar $totalUnidadesLabel' : 'Cobrar',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
    );
  }
}

class _AccountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AccountChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.sunken,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? colors.onAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.sunken,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.add, size: 20, color: colors.textSecondary),
      ),
    );
  }
}

/// Fila de artículo: "N × nombre", precio, y "−"/"+" como botones cuadrados
/// con borde, según la vista objetivo del sistema de diseño.
class _CartLine extends StatelessWidget {
  final CartItemModel item;

  const _CartLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cartProvider = context.read<CartProvider>();
    final productosProvider = context.watch<ProductosProvider>();
    final isOnline = context.watch<SyncProvider>().isOnline;
    final monedas = context.watch<MonedasProvider>();
    final allProductos = productosProvider.allProductos;

    ProductoModel? producto;
    try {
      producto = allProductos.firstWhere((p) => p.id == item.productoTiendaId);
    } catch (_) {
      producto = null;
    }

    final disponible = producto != null
        ? ProductoPosRules.getMaxQuantity(
            producto,
            allProductos,
            cantidadEnCarrito: item.cantidad,
            offlineMode: !isOnline,
          )
        : double.infinity;
    final maxTotal = producto != null && disponible.isFinite
        ? item.cantidad + disponible
        : double.infinity;
    final canIncrement = maxTotal.isInfinite || item.cantidad < maxTotal;
    final decrementQty = producto?.permiteDecimal == true
        ? (item.cantidad - 0.1).clamp(0.1, double.infinity)
        : (item.cantidad - 1).roundToDouble().clamp(1.0, double.infinity);

    void onDecrement() {
      if (item.cantidad <= (producto?.permiteDecimal == true ? 0.1 : 1)) {
        cartProvider.removeItemById(item.productoTiendaId);
      } else {
        cartProvider.updateItemCantidadById(
          item.productoTiendaId,
          decrementQty,
          allProductos: producto != null ? allProductos : null,
          producto: producto,
          isOnline: isOnline,
        );
      }
    }

    void onIncrement() {
      final newQty = producto?.permiteDecimal == true
          ? double.parse((item.cantidad + 0.1).toStringAsFixed(2))
          : item.cantidad + 1;
      cartProvider.updateItemCantidadById(
        item.productoTiendaId,
        newQty,
        allProductos: producto != null ? allProductos : null,
        producto: producto,
        isOnline: isOnline,
      );
    }

    final subtotalBase = monedas.convertToBase(
      item.subtotal,
      item.monedaPrecioCode ?? monedas.monedaBase,
    );
    final cantidadText =
        item.cantidad.toStringAsFixed(item.cantidad == item.cantidad.roundToDouble() ? 0 : 1);

    Widget squareButton({required IconData icon, required VoidCallback? onPressed}) {
      return SizedBox(
        width: 36,
        height: 36,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          child: Icon(icon, size: 18, color: colors.textPrimary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            '$cantidadText ×',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.formatNumber(subtotalBase),
            style: tabularNums(const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          squareButton(icon: Icons.remove, onPressed: onDecrement),
          const SizedBox(width: 8),
          squareButton(icon: Icons.add, onPressed: canIncrement ? onIncrement : null),
        ],
      ),
    );
  }
}
