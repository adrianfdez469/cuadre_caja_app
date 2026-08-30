import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/producto_pos_rules.dart';
import '../../../data/models/cart_model.dart';
import '../../../data/models/producto_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../widgets/multi_currency_amount.dart';
import '../../../widgets/stock_local_badge.dart';

/// Fila de un item del carrito con sus controles de cantidad, para el panel
/// del escáner.
///
/// Muta el carrito **por `productoTiendaId`**, no por índice: el panel del
/// escáner reordena la lista al escanear, y un índice capturado en el build
/// podría apuntar a otro producto cuando llega el tap.
class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.allProductos,
    required this.isOnline,
    required this.permitirSinStock,
    this.highlighted = false,
    this.dismissible = true,
  });

  final CartItemModel item;

  /// Catálogo local; lo observa el padre una sola vez por lista.
  final List<ProductoModel> allProductos;

  /// Solo para el aviso visual: sin conexión el stock que falta es el de la
  /// caché ("Sin stock local"); con conexión es el real del servidor.
  final bool isOnline;

  /// Si es true no se valida el stock al subir cantidades. Ver `VentaSinStockPolicy`.
  final bool permitirSinStock;

  /// Resalta temporalmente la fila (producto recién escaneado).
  final bool highlighted;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.read<CartProvider>();
    final monedas = context.watch<MonedasProvider>();

    ProductoModel? producto;
    try {
      producto = allProductos.firstWhere((p) => p.id == item.productoTiendaId);
    } catch (_) {
      producto = null;
    }

    final cantidadEnCarrito = item.cantidad;
    final disponible = producto != null
        ? ProductoPosRules.getMaxQuantity(
            producto,
            allProductos,
            cantidadEnCarrito: cantidadEnCarrito,
            permitirSinStock: permitirSinStock,
          )
        : double.infinity;
    final maxTotalPermitido = producto != null
        ? (disponible.isFinite ? cantidadEnCarrito + disponible : double.infinity)
        : double.infinity;
    final canIncrement =
        maxTotalPermitido.isInfinite || item.cantidad < maxTotalPermitido;
    final sinStockLocal = permitirSinStock &&
        producto != null &&
        !ProductoPosRules.tieneStockLocalEfectivo(
          producto,
          allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
        );
    final decrementQty = producto?.permiteDecimal == true
        ? (item.cantidad - 0.1).clamp(0.1, double.infinity)
        : (item.cantidad - 1).roundToDouble().clamp(1.0, double.infinity);

    final monedaItem = item.monedaPrecioCode ?? producto?.monedaPrecioCode;
    final subtotalBase = monedas.convertToBase(
      item.subtotal,
      monedaItem ?? monedas.monedaBase,
    );

    void onDecrement() {
      if (item.cantidad <= (producto?.permiteDecimal == true ? 0.1 : 1)) {
        cartProvider.removeItemById(item.productoTiendaId);
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

    Future<void> onIncrement() async {
      final newQty = producto?.permiteDecimal == true
          ? double.parse((item.cantidad + 0.1).toStringAsFixed(2))
          : item.cantidad + 1;
      await cartProvider.updateItemCantidadById(
        item.productoTiendaId,
        newQty,
        allProductos: producto != null ? allProductos : null,
        producto: producto,
        permitirSinStock: permitirSinStock,
      );
    }

    final colors = context.colors;

    final card = _buildCard(
      context: context,
      colors: colors,
      sinStockLocal: sinStockLocal,
      subtotalBase: subtotalBase,
      canIncrement: canIncrement,
      onDecrement: onDecrement,
      onIncrement: onIncrement,
    );

    if (!dismissible) return card;

    return Dismissible(
      key: Key(item.productoTiendaId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colors.negative,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => cartProvider.removeItemById(item.productoTiendaId),
      child: card,
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required AppSemanticColors colors,
    required bool sinStockLocal,
    required double subtotalBase,
    required bool canIncrement,
    required VoidCallback onDecrement,
    required Future<void> Function() onIncrement,
  }) {
    // El naranja de "sin stock local" tiene prioridad sobre el resaltado verde:
    // es una señal de negocio y no debe perderse al escanear.
    final baseColor =
        SinStockLocalStyles.cardColor(context, sinStockLocal: sinStockLocal);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: _buildCompactBody(
        colors: colors,
        sinStockLocal: sinStockLocal,
        subtotalBase: subtotalBase,
        canIncrement: canIncrement,
        onDecrement: onDecrement,
        onIncrement: onIncrement,
      ),
    );

    final card = Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: baseColor,
      shape: SinStockLocalStyles.cardShape(context, sinStockLocal: sinStockLocal),
      child: content,
    );

    if (!highlighted || sinStockLocal) return card;

    // Destello verde que se desvanece solo, para ubicar de un vistazo el
    // producto que acaba de entrar por escaneo.
    return TweenAnimationBuilder<double>(
      key: ValueKey('hl-${item.productoTiendaId}-${item.cantidad}'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (_, t, child) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        color: Color.lerp(
          baseColor ?? Theme.of(context).cardColor,
          colors.positive.withValues(alpha: 0.28),
          t,
        ),
        shape: SinStockLocalStyles.cardShape(context, sinStockLocal: sinStockLocal),
        child: child,
      ),
      child: content,
    );
  }

  Widget _buildCompactBody({
    required AppSemanticColors colors,
    required bool sinStockLocal,
    required double subtotalBase,
    required bool canIncrement,
    required VoidCallback onDecrement,
    required Future<void> Function() onIncrement,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (sinStockLocal) ...[
                const SizedBox(height: 2),
                StockLocalBadge(compact: true, isOnline: isOnline),
              ],
              MultiCurrencyAmount(
                amount: subtotalBase,
                variant: MultiCurrencyVariant.compact,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _buildStepper(
          colors: colors,
          canIncrement: canIncrement,
          onDecrement: onDecrement,
          onIncrement: onIncrement,
          iconSize: 24,
        ),
      ],
    );
  }

  /// Controles − / cantidad / +. Los targets táctiles se mantienen en 36x36
  /// también en compacto: es un POS que se usa con el dedo.
  Widget _buildStepper({
    required AppSemanticColors colors,
    required bool canIncrement,
    required VoidCallback onDecrement,
    required Future<void> Function() onIncrement,
    double iconSize = 26,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onDecrement,
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          color: colors.negative,
        ),
        SizedBox(
          width: 36,
          child: Text(
            item.cantidad.toStringAsFixed(
              item.cantidad == item.cantidad.roundToDouble() ? 0 : 1,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: canIncrement ? onIncrement : null,
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          color: colors.positive,
        ),
      ],
    );
  }
}
