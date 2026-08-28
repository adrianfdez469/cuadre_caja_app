import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/producto_pos_rules.dart';
import '../../../data/models/cart_model.dart';
import '../../../data/models/producto_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../providers/productos_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../widgets/multi_currency_amount.dart';
import 'accounts_sheet.dart';
import '../payment_modal.dart';

/// Barra de cobro fija de la pantalla de venta (Dirección B "Pulgar"): el
/// total nunca se abre, nunca se tapa. Reemplaza la navegación a una
/// pantalla de carrito aparte — todo vive en esta franja inferior.
class PosCheckoutBar extends StatefulWidget {
  const PosCheckoutBar({super.key});

  @override
  State<PosCheckoutBar> createState() => _PosCheckoutBarState();
}

class _PosCheckoutBarState extends State<PosCheckoutBar> {
  bool _expanded = false;

  Future<void> _cobrar() async {
    await PaymentModal.show(context);
    if (mounted) setState(() => _expanded = false);
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
                InkWell(
                  onTap: items.isEmpty
                      ? null
                      : () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${items.length} ${items.length == 1 ? 'artículo' : 'artículos'}',
                        style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: colors.onInverseMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_expanded && items.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.onInverseMuted.withValues(alpha: 0.25))),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) => _CheckoutLine(item: items[index]),
                ),
              ),
            ],
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
              onPressed: habilitado ? _cobrar : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
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
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
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

/// Fila de carrito dentro de la barra de cobro invertida: sin tarjeta, texto
/// claro sobre fondo oscuro, "− n +" para corregir (según `.b-lines` de
/// `pos-mobile-4-variantes.html`).
class _CheckoutLine extends StatelessWidget {
  final CartItemModel item;

  const _CheckoutLine({required this.item});

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

    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.onInverseMuted.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${item.cantidad.toStringAsFixed(item.cantidad == item.cantidad.roundToDouble() ? 0 : 1)} ×',
              style: TextStyle(fontSize: 12.5, color: colors.onInverse),
            ),
          ),
          Expanded(
            child: Text(
              item.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: colors.onInverseMuted),
            ),
          ),
          Text(
            Formatters.formatNumber(subtotalBase),
            style: tabularNums(TextStyle(fontSize: 12.5, color: colors.onInverse)),
          ),
          SizedBox(
            width: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 16),
                  color: colors.onInverse,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onDecrement,
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 16),
                  color: colors.onInverse,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: canIncrement ? onIncrement : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
