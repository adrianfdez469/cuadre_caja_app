import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../data/models/categoria_model.dart';
import '../../data/models/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/hardware_scanner_gate.dart';
import '../../providers/cart_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../widgets/multi_currency_amount.dart';
import '../../widgets/stock_local_badge.dart';

class ProductosScreen extends StatefulWidget {
  final CategoriaModel categoria;

  const ProductosScreen({super.key, required this.categoria});

  @override
  State<ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    // Limpiar filtro al salir
    context.read<ProductosProvider>().filterByCategoria(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productosProvider = context.watch<ProductosProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoria.nombre.trim()),
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar en ${widget.categoria.nombre.trim()}...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          productosProvider.searchProductos('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: productosProvider.searchProductos,
            ),
          ),
        ),
      ),
      body: productosProvider.productos.isEmpty
          ? _buildEmptyState()
          : _buildProductsList(productosProvider.productos),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'No se encontraron productos',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList(List<ProductoModel> productos) {
    final cart = context.watch<CartProvider>().activeCart;
    final allProductos = context.read<ProductosProvider>().allProductos;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: productos.length,
      itemBuilder: (context, index) {
        final producto = productos[index];
        final cantidadEnCarrito = cart?.items
                .where((i) => i.productoTiendaId == producto.id)
                .fold<double>(0, (s, i) => s + i.cantidad) ??
            0;
        return _ProductCard(
          producto: producto,
          allProductos: allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductoModel producto;
  final List<ProductoModel> allProductos;
  final double cantidadEnCarrito;

  const _ProductCard({
    required this.producto,
    required this.allProductos,
    this.cantidadEnCarrito = 0,
  });

  @override
  Widget build(BuildContext context) {
    final monedas = context.watch<MonedasProvider>();
    final isOnline = context.watch<SyncProvider>().isOnline;
    final offlineMode = !isOnline;
    final disponible = ProductoPosRules.disponibleParaMostrar(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );
    final puedeAgregar = ProductoPosRules.puedeAgregar(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );
    final sinStockLocal = offlineMode &&
        !ProductoPosRules.tieneStockLocalEfectivo(
          producto,
          allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
        );
    final hasStock = isOnline
        ? disponible > 0
        : ProductoPosRules.tieneStockLocalEfectivo(
            producto,
            allProductos,
            cantidadEnCarrito: cantidadEnCarrito,
          );
    final stockText = ProductoPosRules.textoStockEnCard(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: SinStockLocalStyles.cardColor(sinStockLocal: sinStockLocal),
      shape: SinStockLocalStyles.cardShape(sinStockLocal: sinStockLocal),
      child: InkWell(
        onTap: puedeAgregar ? () => _showQuantityDialog(context, isOnline) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductoPosRules.nombreParaMostrar(producto),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (sinStockLocal) ...[
                      const SizedBox(height: 6),
                      const StockLocalBadge(compact: true),
                    ],
                    if (producto.descripcion?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        producto.descripcion!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MultiCurrencyAmount(
                          amount: monedas.precioEnBase(
                            producto.precio,
                            producto.monedaPrecioCode,
                          ),
                          variant: MultiCurrencyVariant.product,
                        ),
                        if (stockText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: hasStock
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              stockText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: hasStock
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.add_shopping_cart,
                  color: puedeAgregar ? AppColors.success : AppColors.textHint,
                ),
                onPressed:
                    puedeAgregar ? () => _addToCart(context, isOnline) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToCart(BuildContext context, bool isOnline) async {
    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final offlineMode = !isOnline;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );
    final qty = (maxDisp >= 1) ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    if (qty > maxDisp) return;
    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: qty,
          allProductos: allProductos,
          isOnline: isOnline,
        );
    if (!context.mounted) return;
    if (ok) {
      AppSnackBar.show(
        context,
        content: Text('${ProductoPosRules.nombreParaMostrar(producto)} agregado'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
      );
      if (offlineMode &&
          !ProductoPosRules.tieneStockLocalEfectivo(
            producto,
            allProductos,
            cantidadEnCarrito: cantidadEnCarrito + qty,
          )) {
        AppSnackBar.show(
          context,
          content: const Text('Venta sin stock local — se validará al sincronizar'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  void _showQuantityDialog(BuildContext context, bool isOnline) {
    final productosProvider = context.read<ProductosProvider>();
    final cart = context.read<CartProvider>().activeCart;
    final offlineMode = !isOnline;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );
    if (!offlineMode && maxDisp <= 0) return;
    final initialQty = producto.permiteDecimal ? 0.1 : 1.0;
    final controller = TextEditingController(
      text: initialQty.toStringAsFixed(producto.permiteDecimal ? 1 : 0),
    );

    String stockLabel() => ProductoPosRules.textoStockEnDialogo(
          producto,
          productosProvider.allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
          offlineMode: offlineMode,
        );

    HardwareScannerGate.instance.block('product_dialog');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          double? parseQty() {
            final v = double.tryParse(controller.text.replaceAll(',', '.'));
            if (v == null) return null;
            return producto.permiteDecimal
                ? double.tryParse(v.toStringAsFixed(2))
                : v.roundToDouble().toDouble();
          }

          void adjustQty(double delta) {
            final current = parseQty() ?? initialQty;
            var next = current + delta;
            if (producto.permiteDecimal) {
              next = (next * 100).round() / 100;
              if (next < 0.1) next = 0.1;
            } else {
              next = next.roundToDouble();
              if (next < 1) next = 1;
            }
            if (maxDisp.isFinite && next > maxDisp) next = maxDisp;
            controller.text =
                next.toStringAsFixed(producto.permiteDecimal ? 2 : 0);
            setState(() {});
          }

          return AlertDialog(
            title: Text(ProductoPosRules.nombreParaMostrar(producto)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MultiCurrencyAmount(
                  amount: context.read<MonedasProvider>().precioEnBase(
                        producto.precio,
                        producto.monedaPrecioCode,
                      ),
                  variant: MultiCurrencyVariant.total,
                ),
                const SizedBox(height: 8),
                Text(
                  stockLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: producto.permiteDecimal
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
                if (producto.permiteDecimal) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...([0.01, 0.1, 0.5, 1, 10, 50, 100]
                          .map((d) => ActionChip(
                                label: Text('+$d'),
                                onPressed: () => adjustQty(d.toDouble()),
                              ))),
                      ...([-0.01, -0.1, -0.5, -1, -10, -50, -100]
                          .map((d) => ActionChip(
                                label: Text('$d'),
                                onPressed: () => adjustQty(d.toDouble()),
                              ))),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  var cantidad = parseQty();
                  if (cantidad == null || cantidad <= 0) return;
                  if (producto.permiteDecimal) {
                    cantidad = double.parse(cantidad.toStringAsFixed(2));
                  }
                  if (maxDisp.isFinite && cantidad > maxDisp) return;

                  Navigator.pop(ctx);
                  final ok = await context.read<CartProvider>().addToCart(
                        producto,
                        cantidad: cantidad,
                        allProductos: productosProvider.allProductos,
                        isOnline: isOnline,
                      );

                  if (!context.mounted) return;
                  if (ok) {
                    AppSnackBar.show(
                      context,
                      content: Text(
                          '${ProductoPosRules.nombreParaMostrar(producto)} x$cantidad agregado'),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 1),
                    );
                  } else {
                    AppSnackBar.show(
                      context,
                      content: const Text(
                          'Cantidad supera el máximo disponible'),
                      backgroundColor: AppColors.error,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Agregar'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(
      () => HardwareScannerGate.instance.unblock('product_dialog'),
    );
  }
}
