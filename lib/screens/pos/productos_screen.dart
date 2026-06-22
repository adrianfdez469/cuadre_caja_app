import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../data/models/categoria_model.dart';
import '../../data/models/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../services/hardware_scanner_gate.dart';
import '../../providers/cart_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../widgets/multi_currency_amount.dart';

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
    final disponible = ProductoPosRules.disponibleParaMostrar(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
    );
    final hasStock = disponible > 0;
    final esFraccion = ProductoPosRules.isFraccion(producto);
    final existenciaReal = ProductoPosRules.existenciaReal(producto);
    final stockText = esFraccion
        ? 'Stock: ${existenciaReal.toStringAsFixed(producto.permiteDecimal ? 1 : 0)} | Máx: ${disponible.toStringAsFixed(producto.permiteDecimal ? 1 : 0)}'
        : 'Cant: ${disponible.toStringAsFixed(producto.permiteDecimal ? 1 : 0)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: hasStock ? () => _showQuantityDialog(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductoPosRules.nombreParaMostrar(producto),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (producto.descripcion?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        producto.descripcion!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: MultiCurrencyAmount(
                            amount: monedas.precioEnBase(
                              producto.precio,
                              producto.monedaPrecioCode,
                            ),
                            variant: MultiCurrencyVariant.product,
                          ),
                        ),
                        const SizedBox(width: 12),
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

              // Add button
              IconButton(
                icon: Icon(
                  Icons.add_shopping_cart,
                  color: hasStock ? AppColors.success : AppColors.textHint,
                ),
                onPressed: hasStock ? () => _addToCart(context) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToCart(BuildContext context) async {
    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
    );
    final qty = (maxDisp >= 1) ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    if (qty > maxDisp) return;
    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: qty,
          allProductos: allProductos,
        );
    if (!context.mounted) return;
    if (ok) {
      AppSnackBar.show(
        context,
        content: Text('${ProductoPosRules.nombreParaMostrar(producto)} agregado'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
      );
    }
  }

  void _showQuantityDialog(BuildContext context) {
    final productosProvider = context.read<ProductosProvider>();
    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
    );
    final esFraccion = ProductoPosRules.isFraccion(producto);
    final existenciaReal = ProductoPosRules.existenciaReal(producto);
    final initialQty = producto.permiteDecimal ? 0.1 : 1.0;
    final controller = TextEditingController(
      text: initialQty.toStringAsFixed(producto.permiteDecimal ? 1 : 0),
    );

    String stockLabel() {
      if (esFraccion) {
        return 'Stock: ${existenciaReal.toStringAsFixed(producto.permiteDecimal ? 1 : 0)} | Máx. por venta: ${maxDisp.toStringAsFixed(producto.permiteDecimal ? 1 : 0)}';
      }
      return 'Disponibles: ${maxDisp.toStringAsFixed(producto.permiteDecimal ? 1 : 0)}';
    }

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
            if (next > maxDisp) next = maxDisp;
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
                  if (cantidad > maxDisp) return;

                  Navigator.pop(ctx);
                  final ok = await context.read<CartProvider>().addToCart(
                        producto,
                        cantidad: cantidad,
                        allProductos: productosProvider.allProductos,
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
