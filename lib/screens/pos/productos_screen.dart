import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/categoria_model.dart';
import '../../data/models/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../providers/cart_provider.dart';

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
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: productos.length,
      itemBuilder: (context, index) {
        final producto = productos[index];
        return _ProductCard(producto: producto);
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductoModel producto;

  const _ProductCard({required this.producto});

  @override
  Widget build(BuildContext context) {
    final hasStock = producto.hasStock;

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
                      producto.nombre,
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
                      children: [
                        Text(
                          Formatters.formatCurrency(producto.precio),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
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
                            'Stock: ${producto.existencia.toStringAsFixed(producto.permiteDecimal ? 1 : 0)}',
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
    await context.read<CartProvider>().addToCart(producto);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${producto.nombre} agregado'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showQuantityDialog(BuildContext context) {
    final controller = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(producto.nombre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Formatters.formatCurrency(producto.precio),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
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
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cantidad = double.tryParse(controller.text);
              if (cantidad == null || cantidad <= 0) return;

              Navigator.pop(ctx);
              await context
                  .read<CartProvider>()
                  .addToCart(producto, cantidad: cantidad);

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${producto.nombre} x$cantidad agregado'),
                  backgroundColor: AppColors.success,
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }
}
