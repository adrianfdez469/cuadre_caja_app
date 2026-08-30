import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../core/utils/slide_route.dart';
import '../../data/models/cart_model.dart';
import '../../data/models/producto_model.dart';
import '../../providers/cart_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/productos_provider.dart';
import '../../core/utils/venta_sin_stock_policy.dart';
import '../../widgets/hardware_scanner_listener.dart';
import '../../widgets/multi_currency_amount.dart';
import 'cobrar_screen.dart';
import 'widgets/accounts_sheet.dart';
import 'widgets/cobrar_button.dart';

/// Abre [CartItemsScreen] con una transición de derecha a izquierda (como un
/// panel que entra desde el borde), en vez del `Navigator.push` con la
/// animación por defecto de la plataforma.
///
/// [onCobrar] reemplaza la acción del botón de cobro. Lo usa la pantalla de
/// cobro, que abre este detalle por encima de sí misma: ahí "Cobrar" solo
/// cierra, porque ya se está cobrando.
Future<void> showCartItemsScreen(BuildContext context, {VoidCallback? onCobrar}) {
  return Navigator.of(context).push(
    slideFromRightRoute<void>(CartItemsScreen(onCobrar: onCobrar)),
  );
}

/// Vista "En la venta": el carrito de la cuenta activa a pantalla completa,
/// con los chips de cuenta arriba (cambiar/crear) y el mismo pie de cobro que
/// la pantalla de venta. Se abre desde "N artículos" en la barra de cobro.
class CartItemsScreen extends StatelessWidget {
  /// Ver [showCartItemsScreen].
  final VoidCallback? onCobrar;

  const CartItemsScreen({super.key, this.onCobrar});

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
          child: CartPanel(
            onClose: () => Navigator.pop(context),
            onCobrar: onCobrar,
          ),
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

  /// `null` abre la pantalla de cobro; ver [showCartItemsScreen].
  final VoidCallback? onCobrar;

  const CartPanel({super.key, this.onClose, this.onCobrar});

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
    final totalUnidadesLabel = Formatters.formatUnidades(totalUnidades);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
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
                          // Crea con nombre consecutivo, la deja activa y
                          // cierra la vista: se vuelve al catálogo listo para
                          // agregarle productos.
                          onTap: () async {
                            await cartProvider.createNextCart();
                            onClose?.call();
                          },
                        );
                      }
                      final cart = cartProvider.carts[index];
                      // La cuenta activa despliega su menú; las demás solo
                      // cambian de cuenta.
                      if (index == cartProvider.activeCartIndex) {
                        return _AccountMenu(
                          cartProvider: cartProvider,
                          index: index,
                          onCerrarVista: onClose,
                        );
                      }
                      return _AccountChip(
                        label: cart.nombre,
                        selected: false,
                        onTap: () => cartProvider.switchCart(index),
                      );
                    },
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  // Unidades, igual que el pie y el botón de cobro: antes esta
                  // línea contaba tipos de producto y decía otro número.
                  'EN LA VENTA · ${totalUnidadesLabel.toUpperCase()}',
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
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, thickness: 1, color: colors.border),
                      itemBuilder: (context, index) => _CartLine(
                        item: items[index],
                        onCerrarVista: onClose,
                      ),
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
                    CobrarButton(
                      unidades: totalUnidades,
                      onPressed: habilitado
                          ? (onCobrar ?? () => showCobrarScreen(context))
                          : null,
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

  /// `null` cuando el chip vive dentro de [_AccountMenu]: ahí el gesto lo
  /// maneja el `PopupMenuButton` que lo envuelve.
  final VoidCallback? onTap;

  /// Solo en el chip activo: anuncia que ahí se despliega el menú.
  final bool showChevron;

  const _AccountChip({
    required this.label,
    required this.selected,
    this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onAccent : colors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: 36,
        padding: EdgeInsets.only(left: 16, right: showChevron ? 10 : 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.sunken,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: foreground),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip de la cuenta activa con su menú de acciones. Reemplaza al botón de 3
/// puntos que antes vivía suelto en la cabecera.
///
/// La cuenta principal (índice 0) no se renombra ni se cierra: es la que
/// sobrevive a cada venta. Sus ítems se muestran igual pero deshabilitados,
/// para que el menú no cambie de forma entre cuentas.
class _AccountMenu extends StatelessWidget {
  final CartProvider cartProvider;
  final int index;

  /// Cierra la vista ampliada al vaciar la cuenta: sin productos no queda nada
  /// que mirar acá. `null` en el panel lateral de tablet, que no es una ruta.
  final VoidCallback? onCerrarVista;

  const _AccountMenu({
    required this.cartProvider,
    required this.index,
    this.onCerrarVista,
  });

  PopupMenuItem<String> _item(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
    required bool enabled,
  }) {
    final colors = context.colors;
    // Material atenúa el texto del ítem deshabilitado, pero no el ícono.
    final color = enabled ? colors.textSecondary : colors.textDisabled;
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              color: enabled ? colors.textPrimary : colors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cart = cartProvider.carts[index];
    final esPrincipal = index == 0;

    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      color: colors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      onSelected: (value) {
        switch (value) {
          case 'renombrar':
            showRenameCartDialog(context, cartProvider, index);
            break;
          case 'vaciar':
            confirmClearCart(
              context,
              cartProvider,
              index,
              alVaciar: onCerrarVista,
            );
            break;
          case 'cerrar':
            confirmCloseCart(context, cartProvider, index);
            break;
        }
      },
      itemBuilder: (context) => [
        _item(
          context,
          value: 'renombrar',
          icon: Icons.edit_outlined,
          label: 'Cambiar nombre',
          enabled: !esPrincipal,
        ),
        _item(
          context,
          value: 'vaciar',
          icon: Icons.delete_outline,
          label: 'Vaciar carrito',
          enabled: cart.items.isNotEmpty,
        ),
        _item(
          context,
          value: 'cerrar',
          icon: Icons.close,
          label: 'Cerrar cuenta',
          enabled: !esPrincipal,
        ),
      ],
      child: _AccountChip(
        label: cart.nombre,
        selected: true,
        showChevron: true,
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

  /// Cierra la vista ampliada cuando esta línea era la última: sin productos
  /// no queda nada que mirar acá. `null` en el panel lateral de tablet.
  final VoidCallback? onCerrarVista;

  const _CartLine({required this.item, this.onCerrarVista});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cartProvider = context.read<CartProvider>();
    final productosProvider = context.watch<ProductosProvider>();
    final permitirSinStock = VentaSinStockPolicy.of(context);
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
            permitirSinStock: permitirSinStock,
          )
        : double.infinity;
    final maxTotal = producto != null && disponible.isFinite
        ? item.cantidad + disponible
        : double.infinity;
    final canIncrement = maxTotal.isInfinite || item.cantidad < maxTotal;
    final decrementQty = producto?.permiteDecimal == true
        ? (item.cantidad - 0.1).clamp(0.1, double.infinity)
        : (item.cantidad - 1).roundToDouble().clamp(1.0, double.infinity);

    void onDecrement() async {
      if (item.cantidad <= (producto?.permiteDecimal == true ? 0.1 : 1)) {
        await cartProvider.removeItemById(item.productoTiendaId);
        // Bajar la última unidad deja la cuenta vacía: mismo destino que
        // "Vaciar carrito" — saltar a otra cuenta con venta en curso, o volver
        // al catálogo si no queda ninguna.
        if (cartProvider.activeCart?.isEmpty ?? false) {
          cartProvider.selectFirstNonEmptyCart();
          if (cartProvider.activeCart?.isEmpty ?? true) onCerrarVista?.call();
        }
      } else {
        cartProvider.updateItemCantidadById(
          item.productoTiendaId,
          decrementQty,
          allProductos: producto != null ? allProductos : null,
          producto: producto,
          permitirSinStock: permitirSinStock,
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
        permitirSinStock: permitirSinStock,
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
