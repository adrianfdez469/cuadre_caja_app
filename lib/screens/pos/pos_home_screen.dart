import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../data/models/producto_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../services/sync_service.dart';
import '../login_screen.dart';
import 'cart_screen.dart';
import 'ventas_list_screen.dart';
import 'productos_vendidos_screen.dart';
import 'barcode_scanner_screen.dart';
import '../version_screen.dart';
import 'widgets/categorias_grid.dart';
import 'widgets/connection_indicator.dart';

class POSHomeScreen extends StatefulWidget {
  const POSHomeScreen({super.key});

  @override
  State<POSHomeScreen> createState() => _POSHomeScreenState();
}

class _POSHomeScreenState extends State<POSHomeScreen> {
  bool _isInitialized = false;
  String? _initError;
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final auth = context.read<AuthProvider>();
    final sync = context.read<SyncProvider>();
    final tiendaId = auth.tiendaId;

    if (tiendaId.isEmpty) {
      setState(() => _initError = 'No hay tienda seleccionada');
      return;
    }

    // Configurar callback para cuando se necesite re-auth
    final syncService = context.read<SyncService>();
    syncService.onAuthRequired = (needsLogin) {
      if (needsLogin && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    };

    syncService.onDataRefreshed = () {
      if (mounted) {
        _loadData();
      }
    };

    syncService.onTokenRefreshed = () {
      if (mounted) {
        context.read<AuthProvider>().reloadUserFromStorage();
      }
    };

    // Iniciar monitoreo y esperar al primer chequeo de conectividad (evita "no hay período" en primera instalación)
    await sync.startMonitoring();

    // Cargar datos (ya sabemos si hay conexión; si hay, se traen período y productos del servidor)
    await _loadData();

    setState(() => _isInitialized = true);
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final tiendaId = auth.tiendaId;

    try {
      // Cargar en paralelo: productos, período, carrito y ventas pendientes
      await Future.wait([
        context.read<ProductosProvider>().loadProductos(tiendaId),
        context.read<PeriodoProvider>().loadPeriodo(tiendaId),
        context.read<CartProvider>().init(tiendaId),
        context.read<VentasProvider>().refreshPendientes(),
      ]);

      // Full sync si hay conexión (ventas pendientes + productos, período, destinos)
      context.read<SyncProvider>().fullSync(tiendaId);

      // Cargar y guardar listado unificado de ventas (servidor + local) para no depender de abrir "Ventas y sincronización"
      final periodoId = context.read<PeriodoProvider>().periodoId;
      if (periodoId != null && periodoId.isNotEmpty) {
        await context.read<VentasProvider>().loadVentasUnificado(tiendaId, periodoId);
      }
    } catch (e) {
      print('⚠️ Error inicializando: $e');
      setState(() => _initError = e.toString());
    }
  }

  @override
  void dispose() {
    context.read<SyncProvider>().stopMonitoring();
    _searchController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final productosProvider = context.watch<ProductosProvider>();
    final cartProvider = context.watch<CartProvider>();
    final periodoProvider = context.watch<PeriodoProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final ventasProvider = context.watch<VentasProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Punto de Venta', style: TextStyle(fontSize: 18)),
            Text(
              auth.tiendaNombre,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          // Indicador de conexión
          const ConnectionIndicator(),

          // Ventas pendientes
          if (ventasProvider.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  '${ventasProvider.pendingCount} pendientes',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: AppColors.warning,
                visualDensity: VisualDensity.compact,
              ),
            ),

          // Carrito
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              ),
              if (cartProvider.totalItemCountAcrossCarts > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${cartProvider.totalItemCountAcrossCarts}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),

          // Menu
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'ventas',
                child: ListTile(
                  leading: Icon(Icons.receipt_long),
                  title: Text('Ventas y sincronizaciones'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'productos_vendidos',
                child: ListTile(
                  leading: Icon(Icons.shopping_bag),
                  title: Text('Productos Vendidos'),
                  dense: true,
                ),
              ),
              // Oculto hasta decidir si mostrarlo
              // if (auth.locales.length > 1)
              //   const PopupMenuItem(
              //     value: 'cambiar_tienda',
              //     child: ListTile(
              //       leading: Icon(Icons.store),
              //       title: Text('Cambiar tienda'),
              //       dense: true,
              //     ),
              //   ),
              const PopupMenuItem(
                value: 'sync',
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Sincronizar'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'version',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Versión'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Cerrar sesión'),
                  dense: true,
                ),
              ),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'ventas':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VentasListScreen()),
                  );
                  break;
                case 'productos_vendidos':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProductosVendidosScreen()),
                  );
                  break;
                // case 'cambiar_tienda':
                //   _showCambiarTiendaDialog();
                //   break;
                case 'sync':
                  await syncProvider.fullSync(auth.tiendaId);
                  await _loadData();
                  break;
                case 'version':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VersionScreen()),
                  );
                  break;
                case 'logout':
                  _confirmLogout();
                  break;
              }
            },
          ),
        ],
      ),
      body: _buildBody(productosProvider, periodoProvider, syncProvider),
    );
  }

  Widget _buildBody(
    ProductosProvider productosProvider,
    PeriodoProvider periodoProvider,
    SyncProvider syncProvider,
  ) {
    if (!_isInitialized && _initError == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Error: $_initError'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initialize,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    // Verificar período
    if (!periodoProvider.hasActivePeriodo) {
      return _buildNoPeriodoView(periodoProvider);
    }

    // Escáner + pistola arriba | contenido | solo buscador por nombre abajo
    return Column(
      children: [
        // Campo pistola + icono escáner en la misma fila
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeController,
                  decoration: InputDecoration(
                    hintText: 'Código (pistola): escanee y pulse Enter',
                    prefixIcon: const Icon(Icons.qr_code_2, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (value) => _onBarcodeSubmitted(context, value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Sync status bar
        if (syncProvider.lastMessage.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: syncProvider.isOnline
                ? AppColors.success.withOpacity(0.1)
                : AppColors.warning.withOpacity(0.1),
            child: Text(
              syncProvider.lastMessage,
              style: TextStyle(
                fontSize: 12,
                color: syncProvider.isOnline
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ),
          ),

        // Resultados búsqueda o categorías
        Expanded(
          child: _searchQuery.trim().isEmpty
              ? (productosProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : CategoriasGrid(
                      categorias: productosProvider.categorias,
                      productosProvider: productosProvider,
                    ))
              : _BuildSearchResults(
                  query: _searchQuery.trim(),
                  productosProvider: productosProvider,
                  onProductTap: _showAddToCartDialog,
                  onQuickAdd: _quickAddToCart,
                ),
        ),

        // Solo buscador por nombre (parte inferior)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
      ],
    );
  }

  Widget _buildNoPeriodoView(PeriodoProvider periodoProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text(
              'No hay período de caja abierto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Debes abrir un período para comenzar a vender',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: periodoProvider.isLoading
                  ? null
                  : () async {
                      final tiendaId = context.read<AuthProvider>().tiendaId;
                      await periodoProvider.abrirPeriodo(tiendaId);
                    },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Abrir Período'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Oculto hasta decidir si mostrar "Cambiar tienda" en el menú
  // void _showCambiarTiendaDialog() {
  //   final auth = context.read<AuthProvider>();
  //
  //   showDialog(
  //     context: context,
  //     builder: (ctx) => AlertDialog(
  //       title: const Text('Cambiar tienda'),
  //       content: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         children: auth.locales.map((tienda) {
  //           final isActive = tienda.id == auth.tiendaId;
  //           return ListTile(
  //             leading: Icon(
  //               Icons.store,
  //               color: isActive ? AppColors.primary : null,
  //             ),
  //             title: Text(tienda.nombre),
  //             trailing: isActive ? const Icon(Icons.check) : null,
  //             onTap: isActive
  //                 ? null
  //                 : () async {
  //                     Navigator.pop(ctx);
  //                     final ok = await auth.cambiarTienda(tienda.id);
  //                     if (ok && mounted) {
  //                       await _loadData();
  //                     }
  //                   },
  //           );
  //         }).toList(),
  //       ),
  //     ),
  //   );
  // }

  void _confirmLogout() {
    final ventas = context.read<VentasProvider>();

    if (ventas.pendingCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ventas pendientes'),
          content: Text(
            'Tienes ${ventas.pendingCount} ventas sin sincronizar. '
            'Si cierras sesión se perderán. ¿Sincronizar primero?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await ventas.syncPendientes();
              },
              child: const Text('Sincronizar'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _onBarcodeSubmitted(BuildContext context, String code) async {
    if (code.trim().isEmpty) return;
    final productosProvider = context.read<ProductosProvider>();
    final producto = productosProvider.findProductByCodigo(code);
    _barcodeController.clear();
    if (producto == null) {
      AppSnackBar.show(
        context,
        content: const Text('Producto no encontrado para el código escaneado'),
        backgroundColor: AppColors.error,
      );
      return;
    }
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
    if (maxDisp <= 0) {
      AppSnackBar.show(
        context,
        content: const Text('Sin stock'),
        backgroundColor: AppColors.warning,
      );
      return;
    }
    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: qty,
          allProductos: productosProvider.allProductos,
        );
    if (ok) {
      AppSnackBar.show(
        context,
        content: Text('${ProductoPosRules.nombreParaMostrar(producto)} agregado'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
      );
    }
  }

  /// Agregar 1 unidad al carrito desde el icono de acceso rápido (buscador).
  Future<void> _quickAddToCart(BuildContext context, ProductoModel producto) async {
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
    if (maxDisp <= 0) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          content: const Text('Sin stock'),
          backgroundColor: AppColors.warning,
        );
      }
      return;
    }
    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: qty,
          allProductos: productosProvider.allProductos,
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

  void _showAddToCartDialog(BuildContext context, ProductoModel producto) {
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
    if (maxDisp <= 0) return;
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
                Text(
                  Formatters.formatCurrency(producto.precio),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
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
    );
  }
}

/// Lista de resultados de búsqueda por nombre (tiempo real)
class _BuildSearchResults extends StatelessWidget {
  final String query;
  final ProductosProvider productosProvider;
  final void Function(BuildContext context, ProductoModel product) onProductTap;
  final void Function(BuildContext context, ProductoModel product) onQuickAdd;

  const _BuildSearchResults({
    required this.query,
    required this.productosProvider,
    required this.onProductTap,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final results = productosProvider.searchByName(query, limit: 15);

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'Sin coincidencias para "$query"',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final cart = context.watch<CartProvider>().activeCart;
    final allProductos = productosProvider.allProductos;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final p = results[index];
        final cantidadEnCarrito = cart?.items
                .where((i) => i.productoTiendaId == p.id)
                .fold<double>(0, (s, i) => s + i.cantidad) ??
            0;
        final disponible = ProductoPosRules.disponibleParaMostrar(
          p,
          allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
        );
        final hasStock = disponible > 0;
        final esFraccion = ProductoPosRules.isFraccion(p);
        final existenciaReal = ProductoPosRules.existenciaReal(p);
        final stockText = esFraccion
            ? 'Stock: ${existenciaReal.toStringAsFixed(p.permiteDecimal ? 1 : 0)} | Máx: ${disponible.toStringAsFixed(p.permiteDecimal ? 1 : 0)}'
            : 'Cant: ${disponible.toStringAsFixed(p.permiteDecimal ? 1 : 0)}';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              ProductoPosRules.nombreParaMostrar(p),
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: hasStock ? null : AppColors.textSecondary,
              ),
            ),
            subtitle: Text(
              '${Formatters.formatCurrency(p.precio)}  •  $stockText',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: hasStock
                ? IconButton(
                    icon: const Icon(Icons.add_shopping_cart, color: AppColors.success),
                    onPressed: () => onQuickAdd(context, p),
                    tooltip: 'Agregar 1 al carrito',
                  )
                : null,
            onTap: hasStock ? () => onProductTap(context, p) : null,
          ),
        );
      },
    );
  }
}
