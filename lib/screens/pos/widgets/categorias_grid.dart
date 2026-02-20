import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/categoria_model.dart';
import '../../../providers/productos_provider.dart';
import '../productos_screen.dart';

class CategoriasGrid extends StatelessWidget {
  final List<CategoriaModel> categorias;
  final ProductosProvider productosProvider;

  const CategoriasGrid({
    super.key,
    required this.categorias,
    required this.productosProvider,
  });

  @override
  Widget build(BuildContext context) {
    // Mostrar solo categorías que tienen al menos un producto
    final categoriasConProductos = categorias.where((c) {
      return productosProvider.allProductos
          .any((p) => p.categoriaId == c.id);
    }).toList();

    if (categoriasConProductos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              categorias.isEmpty
                  ? 'No hay categorías disponibles'
                  : 'No hay categorías con productos',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              categorias.isEmpty
                  ? 'Sincroniza para cargar productos'
                  : 'Las categorías con 0 productos no se muestran',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
              ),
              itemCount: categoriasConProductos.length,
              itemBuilder: (context, index) {
                final categoria = categoriasConProductos[index];
                final count = productosProvider.allProductos
                    .where((p) => p.categoriaId == categoria.id)
                    .length;
                return _CategoriaCard(
                  categoria: categoria,
                  productCount: count,
                  onTap: () {
                    productosProvider.filterByCategoria(categoria.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductosScreen(
                          categoria: categoria,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriaCard extends StatelessWidget {
  final CategoriaModel categoria;
  final int productCount;
  final VoidCallback onTap;

  const _CategoriaCard({
    required this.categoria,
    required this.productCount,
    required this.onTap,
  });

  Color _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(categoria.color);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                categoria.nombre.trim(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$productCount productos',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.white70,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
