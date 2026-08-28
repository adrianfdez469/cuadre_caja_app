import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/models/cart_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/productos_provider.dart';
import '../../../providers/sync_provider.dart';
import 'cart_checkout_bar.dart';
import 'cart_item_tile.dart';

/// Alto del encabezado fijo del panel: asa (18) + fila del nombre del carrito
/// (20) + barra de total/Cobrar (~86 con el importe en monedas alternativas,
/// que es el caso más alto). Debe cubrir el peor caso porque el
/// SliverPersistentHeader es de alto fijo.
const double kScannerPanelHeaderHeight = 124;

/// Panel del carrito que vive en la mitad inferior de la pantalla del escáner.
///
/// Observa el CartProvider **dentro de sí mismo**: así los cambios del carrito
/// reconstruyen solo el panel y nunca el MobileScanner.
class ScannerCartPanel extends StatefulWidget {
  const ScannerCartPanel({
    super.key,
    required this.scrollController,
    required this.highlightedId,
    required this.onSaleCompleted,
    this.onHandleTap,
  });

  /// Lo aporta el DraggableScrollableSheet; debe ir en el scrollable interno
  /// para que arrastrar sobre la lista mueva el panel.
  final ScrollController scrollController;

  /// Producto recién escaneado, para resaltarlo y subir la lista hasta él.
  final ValueListenable<String?> highlightedId;
  final VoidCallback onSaleCompleted;
  final VoidCallback? onHandleTap;

  @override
  State<ScannerCartPanel> createState() => _ScannerCartPanelState();
}

class _ScannerCartPanelState extends State<ScannerCartPanel> {
  @override
  void initState() {
    super.initState();
    widget.highlightedId.addListener(_scrollToTopOnScan);
  }

  @override
  void didUpdateWidget(ScannerCartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedId != widget.highlightedId) {
      oldWidget.highlightedId.removeListener(_scrollToTopOnScan);
      widget.highlightedId.addListener(_scrollToTopOnScan);
    }
  }

  @override
  void dispose() {
    widget.highlightedId.removeListener(_scrollToTopOnScan);
    super.dispose();
  }

  /// Lo escaneado entra en la posición 0: si el usuario había bajado en la
  /// lista, hay que subirla para que lo vea. `animateTo` no altera la altura
  /// del sheet (solo la posición del scroll interno).
  void _scrollToTopOnScan() {
    if (widget.highlightedId.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.scrollController;
      if (!mounted || !c.hasClients || c.offset <= 0) return;
      c.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final activeCart = cartProvider.activeCart;
    final items = activeCart?.items ?? const [];
    final allProductos = context.watch<ProductosProvider>().allProductos;
    final isOnline = context.watch<SyncProvider>().isOnline;
    final colors = context.colors;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: Material(
        elevation: 12,
        color: colors.raised,
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _PanelHeaderDelegate(
                height: kScannerPanelHeaderHeight,
                child: _buildHeader(
                  nombreCarrito: activeCart?.nombre ?? 'Carrito',
                  items: items,
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyHint(),
              )
            else
              SliverList.builder(
                itemCount: items.length,
                // Key por producto: la lista se reordena al escanear.
                itemBuilder: (_, i) => ValueListenableBuilder<String?>(
                  valueListenable: widget.highlightedId,
                  builder: (_, hid, __) => CartItemTile(
                    key: ValueKey(items[i].productoTiendaId),
                    item: items[i],
                    allProductos: allProductos,
                    isOnline: isOnline,
                    highlighted: hid == items[i].productoTiendaId,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required String nombreCarrito,
    required List<CartItemModel> items,
  }) {
    final cantidadItems = items.length;
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // El asa es tappable además de arrastrable: un toque alterna entre
        // panel plegado y medio.
        GestureDetector(
          onTap: widget.onHandleTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 16,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  nombreCarrito,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                cantidadItems == 1 ? '1 ítem' : '$cantidadItems ítems',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        CartCheckoutBar(
          items: items,
          onSaleCompleted: widget.onSaleCompleted,
        ),
      ],
    );
  }
}

class _PanelHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PanelHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // El hijo debe ocupar exactamente el alto declarado: si mide menos, el
    // sliver reporta un paintExtent menor que el layoutExtent y falla.
    return SizedBox(
      height: height,
      child: Material(color: context.colors.raised, child: child),
    );
  }

  @override
  bool shouldRebuild(_PanelHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 40, color: colors.textDisabled),
            const SizedBox(height: 12),
            Text(
              'Escanea un producto para agregarlo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
