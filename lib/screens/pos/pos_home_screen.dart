import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
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
import 'barcode_scanner_screen.dart';
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
      // Cargar en paralelo
      await Future.wait([
        context.read<ProductosProvider>().loadProductos(tiendaId),
        context.read<PeriodoProvider>().loadPeriodo(tiendaId),
        context.read<CartProvider>().init(tiendaId),
        context.read<VentasProvider>().refreshPendientes(),
      ]);

      // Full sync si hay conexión
      context.read<SyncProvider>().fullSync(tiendaId);
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
              if (cartProvider.activeItemCount > 0)
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
                      '${cartProvider.activeItemCount}',
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
              if (auth.locales.length > 1)
                const PopupMenuItem(
                  value: 'cambiar_tienda',
                  child: ListTile(
                    leading: Icon(Icons.store),
                    title: Text('Cambiar tienda'),
                    dense: true,
                  ),
                ),
              const PopupMenuItem(
                value: 'sync',
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Sincronizar'),
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
                case 'cambiar_tienda':
                  _showCambiarTiendaDialog();
                  break;
                case 'sync':
                  await syncProvider.fullSync(auth.tiendaId);
                  await _loadData();
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

    // Búsqueda por nombre + Sync status bar + contenido
    return Column(
      children: [
        // Búsqueda por nombre + escáner
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
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
        // Campo para pistola de códigos (Enter = buscar y agregar)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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

  void _showCambiarTiendaDialog() {
    final auth = context.read<AuthProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar tienda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: auth.locales.map((tienda) {
            final isActive = tienda.id == auth.tiendaId;
            return ListTile(
              leading: Icon(
                Icons.store,
                color: isActive ? AppColors.primary : null,
              ),
              title: Text(tienda.nombre),
              trailing: isActive ? const Icon(Icons.check) : null,
              onTap: isActive
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final ok = await auth.cambiarTienda(tienda.id);
                      if (ok && mounted) {
                        await _loadData();
                      }
                    },
            );
          }).toList(),
        ),
      ),
    );
  }

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

  void _onBarcodeSubmitted(BuildContext context, String code) {
    if (code.trim().isEmpty) return;
    final producto = context.read<ProductosProvider>().findProductByCodigo(code);
    _barcodeController.clear();
    if (producto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Producto no encontrado para el código escaneado'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!producto.hasStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin stock'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    context.read<CartProvider>().addToCart(producto, cantidad: 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${producto.nombre} agregado'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddToCartDialog(BuildContext context, ProductoModel producto) {
    if (!producto.hasStock) return;
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
              await context.read<CartProvider>().addToCart(producto, cantidad: cantidad);
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

/// Lista de resultados de búsqueda por nombre (tiempo real)
class _BuildSearchResults extends StatelessWidget {
  final String query;
  final ProductosProvider productosProvider;
  final void Function(BuildContext context, ProductoModel product) onProductTap;

  const _BuildSearchResults({
    required this.query,
    required this.productosProvider,
    required this.onProductTap,
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

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final p = results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              p.nombre,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: p.hasStock ? null : AppColors.textSecondary,
              ),
            ),
            subtitle: Text(
              '${Formatters.formatCurrency(p.precio)}  •  Stock: ${p.existencia.toStringAsFixed(p.permiteDecimal ? 1 : 0)}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: p.hasStock
                ? const Icon(Icons.add_shopping_cart, color: AppColors.success)
                : null,
            onTap: p.hasStock ? () => onProductTap(context, p) : null,
          ),
        );
      },
    );
  }
}
