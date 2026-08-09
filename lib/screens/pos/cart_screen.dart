import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/cart_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/sync_provider.dart';
import 'widgets/cart_checkout_bar.dart';
import 'widgets/cart_item_tile.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final activeCart = cartProvider.activeCart;

    return Scaffold(
      appBar: AppBar(
        title: Text(activeCart?.nombre ?? 'Carrito'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (cartProvider.cartCount > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Cambiar carrito',
              itemBuilder: (_) => List.generate(
                cartProvider.cartCount,
                (i) => PopupMenuItem(
                  value: i,
                  child: Row(
                    children: [
                      if (i == cartProvider.activeCartIndex)
                        Icon(Icons.check, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(cartProvider.carts[i].nombre),
                      const Spacer(),
                      Text(
                        '${cartProvider.carts[i].itemCount} items',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              onSelected: cartProvider.switchCart,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nuevo carrito',
            onPressed: () => _createCart(context, cartProvider),
          ),
          if (activeCart != null && activeCart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Vaciar carrito',
              onPressed: () => _confirmClear(context, cartProvider),
            ),
        ],
      ),
      body: activeCart == null || activeCart.isEmpty
          ? _buildEmptyCart(context)
          : _buildCartContent(context, cartProvider),
      bottomNavigationBar: activeCart != null && activeCart.items.isNotEmpty
          ? _buildBottomBar(context, cartProvider)
          : null,
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final canDeleteCart =
        cartProvider.cartCount > 1 && (cartProvider.activeCart?.isEmpty ?? true);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'El carrito está vacío',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Agrega productos desde las categorías',
            style: TextStyle(fontSize: 14, color: AppColors.textHint),
          ),
          if (canDeleteCart) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _confirmDeleteCart(context, cartProvider),
              icon: const Icon(Icons.delete_outline, size: 20),
              label: const Text('Eliminar este carrito'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCartContent(BuildContext context, CartProvider cartProvider) {
    final items = cartProvider.activeCart!.items;
    final allProductos = context.watch<ProductosProvider>().allProductos;
    final isOnline = context.watch<SyncProvider>().isOnline;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      // La key por producto es obligatoria: la lista se reordena al escanear y
      // sin ella Flutter reutilizaría los elementos por posición.
      itemBuilder: (context, index) => CartItemTile(
        key: ValueKey(items[index].productoTiendaId),
        item: items[index],
        allProductos: allProductos,
        isOnline: isOnline,
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, CartProvider cartProvider) {
    return CartCheckoutBar(
      items: cartProvider.activeCart?.items ?? [],
      // Comportamiento histórico de esta pantalla: tras cobrar se vuelve al POS.
      onSaleCompleted: () => Navigator.pop(context),
    );
  }

  void _createCart(BuildContext context, CartProvider cartProvider) {
    final controller =
        TextEditingController(text: 'Carrito ${cartProvider.cartCount + 1}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo carrito'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              cartProvider.createCart(controller.text);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, CartProvider cartProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar carrito'),
        content: const Text('¿Eliminar todos los productos del carrito?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              cartProvider.clearActiveCart();
            },
            child: const Text('Vaciar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCart(BuildContext context, CartProvider cartProvider) {
    final nombre = cartProvider.activeCart?.nombre ?? 'este carrito';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar carrito'),
        content: Text(
          '¿Eliminar "$nombre"? Solo se puede eliminar cuando está vacío.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              cartProvider.deleteCart(cartProvider.activeCartIndex);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
