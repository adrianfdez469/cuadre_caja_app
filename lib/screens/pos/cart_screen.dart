import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../data/models/producto_model.dart';
import '../../providers/cart_provider.dart';
import '../../providers/productos_provider.dart';
import '../../services/hardware_scanner_gate.dart';
import 'payment_modal.dart';

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

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        ProductoModel? producto;
        try {
          producto = allProductos.firstWhere(
            (p) => p.id == item.productoTiendaId,
          );
        } catch (_) {
          producto = null;
        }
        final cantidadEnCarrito = item.cantidad;
        final disponible = producto != null
            ? ProductoPosRules.getMaxQuantity(
                producto,
                allProductos,
                cantidadEnCarrito: cantidadEnCarrito,
              )
            : double.infinity;
        final maxTotalPermitido =
            producto != null ? cantidadEnCarrito + disponible : double.infinity;
        final canIncrement = item.cantidad < maxTotalPermitido;
        final decrementQty = producto?.permiteDecimal == true
            ? (item.cantidad - 0.1).clamp(0.1, double.infinity)
            : (item.cantidad - 1).roundToDouble().clamp(1.0, double.infinity);

        return Dismissible(
          key: Key(item.productoTiendaId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppColors.error,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => cartProvider.removeItem(index),
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${Formatters.formatCurrency(item.precio)} c/u',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cantidad
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          if (item.cantidad <= (producto?.permiteDecimal == true ? 0.1 : 1)) {
                            cartProvider.removeItem(index);
                          } else {
                            cartProvider.updateItemCantidad(
                              index,
                              decrementQty,
                              allProductos: producto != null ? allProductos : null,
                              producto: producto,
                            );
                          }
                        },
                        iconSize: 28,
                        color: AppColors.error,
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          item.cantidad.toStringAsFixed(
                              item.cantidad == item.cantidad.roundToDouble()
                                  ? 0
                                  : 1),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: canIncrement
                            ? () async {
                                final newQty = producto?.permiteDecimal == true
                                    ? double.parse((item.cantidad + 0.1).toStringAsFixed(2))
                                    : item.cantidad + 1;
                                await cartProvider.updateItemCantidad(
                                  index,
                                  newQty,
                                  allProductos: producto != null ? allProductos : null,
                                  producto: producto,
                                );
                              }
                            : null,
                        iconSize: 28,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  // Subtotal
                  SizedBox(
                    width: 80,
                    child: Text(
                      Formatters.formatCurrency(item.subtotal),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, CartProvider cartProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  Formatters.formatCurrency(cartProvider.activeTotal),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _showPaymentModal(context),
                icon: const Icon(Icons.payment),
                label: const Text(
                  'Cobrar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentModal(BuildContext context) {
    HardwareScannerGate.instance.block('payment');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PaymentModal(),
    ).whenComplete(
      () => HardwareScannerGate.instance.unblock('payment'),
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
