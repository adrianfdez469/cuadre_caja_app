import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/sync_error_messages.dart';
import '../../data/models/producto_model.dart';
import '../../data/models/transfer_destination_model.dart';
import '../../data/models/venta_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/productos_provider.dart';
import '../../services/sync_service.dart';
import 'ventas_list_screen.dart';

const _kFilterAll = '_todos_';
const _kFilterOwn = '_propios_';

class VentasDetailScreen extends StatefulWidget {
  final VentaUnificadaModel venta;

  const VentasDetailScreen({super.key, required this.venta});

  @override
  State<VentasDetailScreen> createState() => _VentasDetailScreenState();
}

class _VentasDetailScreenState extends State<VentasDetailScreen> {
  String? _transferDestinationNombre;
  Set<String> _selectedFilters = {_kFilterAll};

  @override
  void initState() {
    super.initState();
    if (widget.venta.transferDestinationId != null &&
        (widget.venta.transferDestinationNombre == null ||
            widget.venta.transferDestinationNombre!.isEmpty)) {
      _resolveTransferDestinationName();
    } else if (widget.venta.transferDestinationNombre != null) {
      _transferDestinationNombre = widget.venta.transferDestinationNombre;
    }
  }

  Future<void> _resolveTransferDestinationName() async {
    final sync = context.read<SyncService>();
    final tiendaId = context.read<AuthProvider>().tiendaId;
    if (tiendaId.isEmpty) return;
    final destinos = await sync.loadTransferDestinations(tiendaId);
    if (!mounted) return;
    final id = widget.venta.transferDestinationId;
    TransferDestinationModel? found;
    for (final d in destinos) {
      if (d.id == id) {
        found = d;
        break;
      }
    }
    setState(() {
      _transferDestinationNombre = found?.nombre;
    });
  }

  /// Mapa productoTiendaId -> proveedor (null o vacío = productos propios)
  Map<String, String?> _proveedorByProducto(List<ProductoModel> allProductos) {
    final map = <String, String?>{};
    for (final p in allProductos) {
      final prov = p.proveedor?.trim();
      map[p.id] = (prov == null || prov.isEmpty) ? null : prov;
    }
    return map;
  }

  /// Proveedores únicos que aparecen en los productos de esta venta (excluyendo propios)
  List<String> _proveedoresEnVenta(Map<String, String?> proveedorByProducto) {
    final set = <String>{};
    for (final vp in widget.venta.productos) {
      final prov = proveedorByProducto[vp.productoTiendaId];
      if (prov != null && prov.isNotEmpty) set.add(prov);
    }
    return set.toList()..sort();
  }

  bool _productoPasaFiltro(
    VentaProducto p,
    Map<String, String?> proveedorByProducto,
    Set<String> selected,
  ) {
    if (selected.contains(_kFilterAll)) return true;
    final prov = proveedorByProducto[p.productoTiendaId];
    final esPropio = prov == null || prov.isEmpty;
    if (esPropio && selected.contains(_kFilterOwn)) return true;
    if (!esPropio && selected.contains(prov)) return true;
    return false;
  }

  List<VentaProducto> _productosFiltrados(
    Map<String, String?> proveedorByProducto,
    Set<String> selected,
  ) {
    return widget.venta.productos
        .where((p) => _productoPasaFiltro(p, proveedorByProducto, selected))
        .toList();
  }

  void _toggleFilter(String key) {
    setState(() {
      if (key == _kFilterAll) {
        if (_selectedFilters.contains(_kFilterAll)) {
          _selectedFilters = _selectedFilters.difference({_kFilterAll});
        } else {
          _selectedFilters = {_kFilterAll};
        }
      } else {
        _selectedFilters = _selectedFilters.difference({_kFilterAll});
        if (_selectedFilters.contains(key)) {
          _selectedFilters = _selectedFilters.difference({key});
        } else {
          _selectedFilters = {..._selectedFilters, key};
        }
      }
      if (_selectedFilters.isEmpty) _selectedFilters = {_kFilterAll};
    });
  }

  @override
  Widget build(BuildContext context) {
    final venta = widget.venta;
    final date = DateTime.fromMillisecondsSinceEpoch(venta.createdAtMs);
    final productosProvider = context.watch<ProductosProvider>();
    final allProductos = productosProvider.allProductos;
    final proveedorByProducto = _proveedorByProducto(allProductos);
    final proveedoresEnVenta = _proveedoresEnVenta(proveedorByProducto);
    final filtrados = _productosFiltrados(proveedorByProducto, _selectedFilters);

    final subtotalFiltrado = filtrados.fold<double>(
      0,
      (s, p) => s + p.precio * p.cantidad,
    );

    final nombreDestino = _transferDestinationNombre ?? venta.transferDestinationNombre;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de venta'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Formatters.formatDateTime(date),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (venta.usuarioNombre != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Usuario: ${venta.usuarioNombre}',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    if (venta.transferDestinationId != null && nombreDestino != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.account_balance_wallet, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'Destino transferencia: $nombreDestino',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (venta.syncState == SyncState.error && (venta.errorMessage?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              Card(
                color: AppColors.syncError.withOpacity(0.08),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppColors.syncError, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              SyncErrorMessages.title(venta.errorMessage),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.syncError,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        SyncErrorMessages.detail(venta.errorMessage),
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => VentasListScreen.showErrorLog(context, venta),
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('Ver log completo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.syncError,
                          side: BorderSide(color: AppColors.syncError),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Totales',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _TotalRow(label: 'Efectivo', value: venta.totalcash),
                    _TotalRow(label: 'Transferencia', value: venta.totaltransfer),
                    if (venta.discountTotal > 0)
                      _TotalRow(label: 'Descuentos', value: -venta.discountTotal),
                    const Divider(),
                    _TotalRow(
                      label: 'Total',
                      value: venta.total,
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filtrar por proveedor',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: 'Todos',
                  selected: _selectedFilters.contains(_kFilterAll),
                  onTap: () => _toggleFilter(_kFilterAll),
                ),
                _FilterChip(
                  label: 'Productos propios',
                  selected: _selectedFilters.contains(_kFilterOwn),
                  onTap: () => _toggleFilter(_kFilterOwn),
                ),
                ...proveedoresEnVenta.map(
                  (prov) => _FilterChip(
                    label: prov,
                    selected: _selectedFilters.contains(prov),
                    onTap: () => _toggleFilter(prov),
                  ),
                ),
              ],
            ),
            if (filtrados.length != venta.productos.length) ...[
              const SizedBox(height: 12),
              Card(
                color: AppColors.primary.withOpacity(0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total (productos filtrados)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        Formatters.formatCurrency(subtotalFiltrado),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Productos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Encabezado: Cant, Precio, Total (nombre va en cada fila a todo el ancho)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: AppColors.primary.withOpacity(0.1),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: Text(
                            'Cant.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                          width: 80,
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
                    itemCount: filtrados.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = filtrados[index];
                      final name = p.name ?? 'Producto';
                      final subtotal = p.precio * p.cantidad;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    Formatters.formatNumber(
                                      p.cantidad,
                                      decimals: p.cantidad == p.cantidad.round() ? 0 : 1,
                                    ),
                                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    Formatters.formatCurrency(p.precio),
                                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    Formatters.formatCurrency(subtotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
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
            ),
          ],
        ),
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

class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isTotal;

  const _TotalRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 15,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            Formatters.formatCurrency(value),
            style: TextStyle(
              fontSize: isTotal ? 18 : 15,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppColors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
