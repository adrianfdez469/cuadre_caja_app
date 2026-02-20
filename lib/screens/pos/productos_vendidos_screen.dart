import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/producto_model.dart';
import '../../data/models/venta_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../services/sync_service.dart';

const _kFilterTodos = '_todos_';
const _kFilterPropios = '_propios_';

enum VistaProductosVendidos { agrupada, historica }

/// Un ítem "vendido" para lista histórica (una línea por venta).
class ProductoVendidoItem {
  final String productoTiendaId;
  final String nombre;
  final double cantidad;
  final double precio;
  final double total;
  final int ventaCreatedAtMs;
  final SyncState syncState;
  final String? proveedorKey; // null o vacío = propios

  ProductoVendidoItem({
    required this.productoTiendaId,
    required this.nombre,
    required this.cantidad,
    required this.precio,
    required this.total,
    required this.ventaCreatedAtMs,
    required this.syncState,
    this.proveedorKey,
  });
}

/// Un ítem agrupado por producto (suma de cantidades y totales).
class ProductoVendidoAgrupado {
  final String productoTiendaId;
  final String nombre;
  final double cantidad;
  final double precioUnitario; // precio representativo (ej. el más reciente)
  final double total;
  final int ultimaVentaMs; // para ordenar: más reciente primero

  ProductoVendidoAgrupado({
    required this.productoTiendaId,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.total,
    required this.ultimaVentaMs,
  });
}

class ProductosVendidosScreen extends StatefulWidget {
  const ProductosVendidosScreen({super.key});

  @override
  State<ProductosVendidosScreen> createState() => _ProductosVendidosScreenState();
}

class _ProductosVendidosScreenState extends State<ProductosVendidosScreen> {
  Set<String> _selectedVendedores = {};
  Set<String> _selectedProveedores = {_kFilterTodos};
  VistaProductosVendidos _vista = VistaProductosVendidos.agrupada;
  Map<String, String> _transferDestinationNames = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _resolveTransferNames();
    });
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final periodo = context.read<PeriodoProvider>();
    if (auth.tiendaId.isEmpty || periodo.periodoId == null) return;
    await context.read<VentasProvider>().loadVentasUnificado(
          auth.tiendaId,
          periodo.periodoId!,
        );
  }

  Future<void> _resolveTransferNames() async {
    final sync = context.read<SyncService>();
    final tiendaId = context.read<AuthProvider>().tiendaId;
    if (tiendaId.isEmpty) return;
    final destinos = await sync.loadTransferDestinations(tiendaId);
    if (!mounted) return;
    setState(() {
      _transferDestinationNames = {
        for (final d in destinos) d.id: d.nombre,
      };
    });
  }

  Map<String, String?> _proveedorByProducto(List<ProductoModel> allProductos) {
    final map = <String, String?>{};
    for (final p in allProductos) {
      final prov = p.proveedor?.trim();
      map[p.id] = (prov == null || prov.isEmpty) ? null : prov;
    }
    return map;
  }

  bool _ventaPasaFiltroVendedor(
    VentaUnificadaModel venta,
    String? currentUserId,
  ) {
    if (_selectedVendedores.isEmpty || _selectedVendedores.contains(_kFilterTodos)) {
      return true;
    }
    final id = venta.usuarioId ?? currentUserId;
    if (id == null) return _selectedVendedores.contains(currentUserId);
    return _selectedVendedores.contains(id);
  }

  bool _productoPasaFiltroProveedor(
    String? proveedorKey,
  ) {
    if (_selectedProveedores.contains(_kFilterTodos)) return true;
    final esPropio = proveedorKey == null || proveedorKey.isEmpty;
    if (esPropio && _selectedProveedores.contains(_kFilterPropios)) return true;
    if (!esPropio && _selectedProveedores.contains(proveedorKey)) return true;
    return false;
  }

  List<VentaUnificadaModel> _ventasFiltradas(
    List<VentaUnificadaModel> ventas,
    String? currentUserId,
  ) {
    return ventas
        .where((v) => _ventaPasaFiltroVendedor(v, currentUserId))
        .toList();
  }

  List<ProductoVendidoItem> _itemsHistoricos(
    List<VentaUnificadaModel> ventasFiltradas,
    Map<String, String?> proveedorByProducto,
  ) {
    final list = <ProductoVendidoItem>[];
    for (final v in ventasFiltradas) {
      for (final p in v.productos) {
        final prov = proveedorByProducto[p.productoTiendaId];
        final provKey = (prov == null || prov.isEmpty) ? null : prov;
        if (!_productoPasaFiltroProveedor(provKey)) continue;
        list.add(ProductoVendidoItem(
          productoTiendaId: p.productoTiendaId,
          nombre: p.name ?? 'Producto',
          cantidad: p.cantidad,
          precio: p.precio,
          total: p.precio * p.cantidad,
          ventaCreatedAtMs: v.createdAtMs,
          syncState: v.syncState,
          proveedorKey: provKey,
        ));
      }
    }
    list.sort((a, b) => b.ventaCreatedAtMs.compareTo(a.ventaCreatedAtMs));
    return list;
  }

  List<ProductoVendidoAgrupado> _itemsAgrupados(
    List<VentaUnificadaModel> ventasFiltradas,
    Map<String, String?> proveedorByProducto,
  ) {
    final map = <String, ProductoVendidoAgrupado>{};
    for (final v in ventasFiltradas) {
      for (final p in v.productos) {
        final prov = proveedorByProducto[p.productoTiendaId];
        final provKey = (prov == null || prov.isEmpty) ? null : prov;
        if (!_productoPasaFiltroProveedor(provKey)) continue;
        final id = p.productoTiendaId;
        final total = p.precio * p.cantidad;
        if (map.containsKey(id)) {
          final existing = map[id]!;
          map[id] = ProductoVendidoAgrupado(
            productoTiendaId: id,
            nombre: existing.nombre,
            cantidad: existing.cantidad + p.cantidad,
            precioUnitario: p.precio,
            total: existing.total + total,
            ultimaVentaMs: existing.ultimaVentaMs > v.createdAtMs
                ? existing.ultimaVentaMs
                : v.createdAtMs,
          );
        } else {
          map[id] = ProductoVendidoAgrupado(
            productoTiendaId: id,
            nombre: p.name ?? 'Producto',
            cantidad: p.cantidad,
            precioUnitario: p.precio,
            total: total,
            ultimaVentaMs: v.createdAtMs,
          );
        }
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.ultimaVentaMs.compareTo(a.ultimaVentaMs));
    return list;
  }

  /// Total vendido solo de ítems que pasan el filtro de proveedor.
  double _totalVendido(
    List<VentaUnificadaModel> ventasFiltradas,
    Map<String, String?> proveedorByProducto,
  ) {
    var total = 0.0;
    for (final v in ventasFiltradas) {
      for (final p in v.productos) {
        if (!_productoPasaFiltroProveedor(proveedorByProducto[p.productoTiendaId])) continue;
        total += p.precio * p.cantidad;
      }
    }
    return total;
  }

  /// Transferencias por destino: solo ventas que tienen al menos un ítem que pasa el filtro de proveedor.
  Map<String, double> _transferenciasPorDestino(
    List<VentaUnificadaModel> ventasFiltradas,
    Map<String, String?> proveedorByProducto,
  ) {
    final map = <String, double>{};
    for (final v in ventasFiltradas) {
      final tieneAlguno = v.productos.any((p) =>
          _productoPasaFiltroProveedor(proveedorByProducto[p.productoTiendaId]));
      if (!tieneAlguno || v.totaltransfer <= 0) continue;
      final id = v.transferDestinationId ?? '_sin_destino_';
      map[id] = (map[id] ?? 0) + v.totaltransfer;
    }
    return map;
  }

  void _initDefaultVendedor(List<VentaUnificadaModel> ventas, String? currentUserId) {
    if (_selectedVendedores.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (currentUserId != null) {
          _selectedVendedores = {currentUserId};
        } else {
          _selectedVendedores = {_kFilterTodos};
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ventasProvider = context.watch<VentasProvider>();
    final productosProvider = context.watch<ProductosProvider>();
    final ventas = ventasProvider.ventasUnificado;
    final currentUser = auth.usuario;
    final currentUserId = currentUser?.id;
    final currentUserNombre = currentUser?.nombre ?? 'Yo';

    if (_selectedVendedores.isEmpty && ventas.isNotEmpty) {
      _initDefaultVendedor(ventas, currentUserId);
    }

    final ventasFiltradas = _ventasFiltradas(ventas, currentUserId);
    final proveedorByProducto = _proveedorByProducto(productosProvider.allProductos);

    final totalVendido = _totalVendido(ventasFiltradas, proveedorByProducto);
    final transferPorDestino = _transferenciasPorDestino(ventasFiltradas, proveedorByProducto);
    final totalTransferencia = transferPorDestino.values.fold<double>(0, (s, v) => s + v);

    final vendedoresOptions = <String, String>{};
    if (currentUserId != null) {
      vendedoresOptions[currentUserId] = currentUserNombre;
    }
    for (final v in ventas) {
      final id = v.usuarioId;
      final name = v.usuarioNombre ?? 'Sin nombre';
      if (id != null && id.isNotEmpty) {
        vendedoresOptions[id] = name;
      }
    }

    final proveedoresOptions = <String>{_kFilterTodos, _kFilterPropios};
    for (final v in ventasFiltradas) {
      for (final p in v.productos) {
        final prov = proveedorByProducto[p.productoTiendaId];
        if (prov != null && prov.isNotEmpty) proveedoresOptions.add(prov);
      }
    }
    final proveedoresList = proveedoresOptions.toList()..sort((a, b) {
      if (a == _kFilterTodos) return -1;
      if (b == _kFilterTodos) return 1;
      if (a == _kFilterPropios) return -1;
      if (b == _kFilterPropios) return 1;
      return a.compareTo(b);
    });

    // Ocultar total transferencia y por destino solo cuando el filtro de proveedor
    // es restrictivo (no "Todos" ni todos los proveedores seleccionados uno por uno).
    final opcionesProveedorSinTodos = proveedoresList.where((x) => x != _kFilterTodos).toList();
    final todosProveedoresSeleccionadosUnoPorUno = opcionesProveedorSinTodos.isNotEmpty &&
        opcionesProveedorSinTodos.every((k) => _selectedProveedores.contains(k));
    final mostrarTransferenciaYDestinos = _selectedProveedores.contains(_kFilterTodos) ||
        todosProveedoresSeleccionadosUnoPorUno;
    final filtroProveedorRestrictivo = !mostrarTransferenciaYDestinos;

    final itemsHistoricos = _vista == VistaProductosVendidos.historica
        ? _itemsHistoricos(ventasFiltradas, proveedorByProducto)
        : <ProductoVendidoItem>[];
    final itemsAgrupados = _vista == VistaProductosVendidos.agrupada
        ? _itemsAgrupados(ventasFiltradas, proveedorByProducto)
        : <ProductoVendidoAgrupado>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos Vendidos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ventasProvider.isLoadingVentas
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                await _resolveTransferNames();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTotales(
                    totalVendido,
                    totalTransferencia,
                    transferPorDestino,
                    filtroProveedorRestrictivo,
                  ),
                  const SizedBox(height: 20),
                  _buildFiltroVendedor(vendedoresOptions, currentUserId),
                  const SizedBox(height: 12),
                  _buildFiltroProveedor(proveedoresList),
                  const SizedBox(height: 12),
                  _buildFiltroVista(),
                  const SizedBox(height: 16),
                  if (_vista == VistaProductosVendidos.agrupada)
                    _buildTablaAgrupada(itemsAgrupados)
                  else
                    _buildTablaHistorica(itemsHistoricos),
                ],
              ),
            ),
    );
  }

  Widget _buildTotales(
    double totalVendido,
    double totalTransferencia,
    Map<String, double> transferPorDestino,
    bool filtroProveedorRestrictivo,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              filtroProveedorRestrictivo ? 'Totales (según filtro proveedor)' : 'Totales',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total vendido:', style: TextStyle(fontSize: 14)),
                Text(
                  Formatters.formatCurrency(totalVendido),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            if (!filtroProveedorRestrictivo) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total en transferencia:', style: TextStyle(fontSize: 14)),
                  Text(
                    Formatters.formatCurrency(totalTransferencia),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            if (!filtroProveedorRestrictivo && transferPorDestino.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Transferencias por destino',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              ...transferPorDestino.entries.map((e) {
                final nombre = e.key == '_sin_destino_'
                    ? 'Sin destino'
                    : (_transferDestinationNames[e.key] ?? e.key);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(nombre, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      Text(
                        Formatters.formatCurrency(e.value),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroVendedor(
    Map<String, String> vendedoresOptions,
    String? currentUserId,
  ) {
    final isTodos = _selectedVendedores.isEmpty || _selectedVendedores.contains(_kFilterTodos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vendido por',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'Todos',
              selected: isTodos,
              onTap: () => setState(() => _selectedVendedores = {_kFilterTodos}),
            ),
            ...vendedoresOptions.entries.map((e) {
              final selected = _selectedVendedores.contains(e.key);
              return _FilterChip(
                label: e.value,
                selected: selected,
                onTap: () => setState(() {
                  if (selected) {
                    _selectedVendedores = _selectedVendedores.difference({e.key});
                    if (_selectedVendedores.isEmpty) _selectedVendedores = {_kFilterTodos};
                  } else {
                    _selectedVendedores = _selectedVendedores.difference({_kFilterTodos});
                    _selectedVendedores = {..._selectedVendedores, e.key};
                  }
                }),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildFiltroProveedor(List<String> proveedoresList) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Proveedor',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: proveedoresList.map((key) {
            final label = key == _kFilterTodos
                ? 'Todos'
                : key == _kFilterPropios
                    ? 'Propios'
                    : key;
            final selected = _selectedProveedores.contains(key);
            return _FilterChip(
              label: label,
              selected: selected,
              onTap: () => setState(() {
                if (key == _kFilterTodos) {
                  if (selected) {
                    _selectedProveedores = _selectedProveedores.difference({key});
                    if (_selectedProveedores.isEmpty) _selectedProveedores = {_kFilterTodos};
                  } else {
                    _selectedProveedores = {_kFilterTodos};
                  }
                } else {
                  _selectedProveedores = _selectedProveedores.difference({_kFilterTodos});
                  if (selected) {
                    _selectedProveedores = _selectedProveedores.difference({key});
                    if (_selectedProveedores.isEmpty) _selectedProveedores = {_kFilterTodos};
                  } else {
                    _selectedProveedores = {..._selectedProveedores, key};
                  }
                }
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFiltroVista() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vista',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Agrupada'),
              selected: _vista == VistaProductosVendidos.agrupada,
              onSelected: (_) => setState(() => _vista = VistaProductosVendidos.agrupada),
              selectedColor: AppColors.primary.withOpacity(0.3),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Histórica'),
              selected: _vista == VistaProductosVendidos.historica,
              onSelected: (_) => setState(() => _vista = VistaProductosVendidos.historica),
              selectedColor: AppColors.primary.withOpacity(0.3),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTablaAgrupada(List<ProductoVendidoAgrupado> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay productos que coincidan con los filtros',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.primary.withOpacity(0.1),
            child: Row(
              children: [
                const SizedBox(width: 4),
                SizedBox(
                  width: 52,
                  child: Text(
                    'Cant.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Precio',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    'Total',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 52,
                          child: Text(
                            Formatters.formatNumber(
                              p.cantidad,
                              decimals: p.cantidad == p.cantidad.round() ? 0 : 1,
                            ),
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            Formatters.formatCurrency(p.precioUnitario),
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: Text(
                            Formatters.formatCurrency(p.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTablaHistorica(List<ProductoVendidoItem> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay productos que coincidan con los filtros',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.primary.withOpacity(0.1),
            child: Row(
              children: [
                const SizedBox(width: 4),
                SizedBox(
                  width: 52,
                  child: Text(
                    'Cant.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Precio',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    'Total',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              final date = DateTime.fromMillisecondsSinceEpoch(p.ventaCreatedAtMs);
              final syncIcon = p.syncState == SyncState.synced
                  ? Icons.cloud_done
                  : p.syncState == SyncState.error
                      ? Icons.cloud_off
                      : p.syncState == SyncState.syncing
                          ? Icons.cloud_sync
                          : Icons.cloud_queue;
              final syncColor = p.syncState == SyncState.synced
                  ? AppColors.synced
                  : p.syncState == SyncState.error
                      ? AppColors.syncError
                      : AppColors.syncing;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 52,
                          child: Text(
                            Formatters.formatNumber(
                              p.cantidad,
                              decimals: p.cantidad == p.cantidad.round() ? 0 : 1,
                            ),
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            Formatters.formatCurrency(p.precio),
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: Text(
                            Formatters.formatCurrency(p.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Formatters.formatDateTime(date),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(syncIcon, size: 18, color: syncColor),
                            const SizedBox(width: 4),
                            Text(
                              p.syncState == SyncState.synced
                                  ? 'Sincronizado'
                                  : p.syncState == SyncState.pending
                                      ? 'Pendiente'
                                      : p.syncState == SyncState.error
                                          ? 'Error'
                                          : 'Sincronizando',
                              style: TextStyle(
                                fontSize: 12,
                                color: syncColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withOpacity(0.3),
      checkmarkColor: AppColors.primary,
    );
  }
}
