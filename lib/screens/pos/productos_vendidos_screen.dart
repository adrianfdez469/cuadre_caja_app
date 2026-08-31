import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/productos_vendidos_agregacion.dart';
import '../../data/models/venta_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../services/sync_service.dart';
import '../../widgets/app_filter_chip.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/sync_badge.dart';
import '../../widgets/sync_state_chip.dart';

enum VistaProductosVendidos { agrupada, historica }

class ProductosVendidosScreen extends StatefulWidget {
  const ProductosVendidosScreen({super.key});

  @override
  State<ProductosVendidosScreen> createState() =>
      _ProductosVendidosScreenState();
}

class _ProductosVendidosScreenState extends State<ProductosVendidosScreen> {
  Set<String> _vendedores = {};
  Set<String> _proveedores = {kFiltroTodos};
  VistaProductosVendidos _vista = VistaProductosVendidos.agrupada;
  OrdenProductosVendidos _orden = OrdenProductosVendidos.importe;
  Map<String, String> _destinos = {};
  bool _vendedorInicializado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarVendedor();
      _load();
      _resolveTransferNames();
    });
  }

  /// Por defecto se muestran las ventas propias. Es una decisión deliberada
  /// —el cajero suele venir a ver lo suyo— pero **tiene que verse**: por eso la
  /// barra de alcance dice siempre qué subconjunto se está mirando.
  void _inicializarVendedor() {
    if (_vendedorInicializado) return;
    final id = context.read<AuthProvider>().usuario?.id;
    setState(() {
      _vendedorInicializado = true;
      _vendedores = id != null ? {id} : {kFiltroTodos};
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
    final destinos = await sync.getTransferDestinationsLocal(tiendaId);
    if (!mounted) return;
    setState(() {
      _destinos = {for (final d in destinos) d.id: d.nombre};
    });
  }

  // ── Opciones de filtro ─────────────────────────────────────────────────────

  Map<String, String> _opcionesVendedor(List<VentaUnificadaModel> ventas) {
    final auth = context.read<AuthProvider>();
    final opciones = <String, String>{};
    final yo = auth.usuario;
    if (yo?.id != null) opciones[yo!.id] = yo.nombre;
    for (final v in ventas) {
      final id = v.usuarioId;
      if (id != null && id.isNotEmpty) {
        opciones[id] = v.usuarioNombre ?? 'Sin nombre';
      }
    }
    return opciones;
  }

  List<String> _opcionesProveedor(
    List<VentaUnificadaModel> ventas,
    Map<String, String?> proveedorPorProducto,
  ) {
    final set = <String>{};
    for (final v in ventas) {
      for (final p in v.productos) {
        final prov = proveedorPorProducto[p.productoTiendaId];
        if (prov != null && prov.isNotEmpty) set.add(prov);
      }
    }
    final list = set.toList()..sort();
    return [kFiltroTodos, kFiltroPropios, ...list];
  }

  /// Cuántos filtros están acotando la vista. Alimenta el badge del botón de
  /// filtros: sin él, un filtro activo escondido en una hoja es invisible.
  int get _filtrosActivos {
    var n = 0;
    if (!(_vendedores.isEmpty || _vendedores.contains(kFiltroTodos))) n++;
    if (!(_proveedores.isEmpty || _proveedores.contains(kFiltroTodos))) n++;
    return n;
  }

  String _textoAlcance(Map<String, String> opcionesVendedor) {
    final miId = context.read<AuthProvider>().usuario?.id;

    String vendedor;
    if (_vendedores.isEmpty || _vendedores.contains(kFiltroTodos)) {
      vendedor = 'Todas las ventas';
    } else if (_vendedores.length == 1) {
      final id = _vendedores.first;
      vendedor = id == miId
          ? 'Tus ventas'
          : (opcionesVendedor[id] ?? 'Un vendedor');
    } else {
      vendedor = '${_vendedores.length} vendedores';
    }

    String proveedor;
    if (_proveedores.isEmpty || _proveedores.contains(kFiltroTodos)) {
      proveedor = 'todos los proveedores';
    } else if (_proveedores.length == 1) {
      final k = _proveedores.first;
      proveedor = k == kFiltroPropios ? 'productos propios' : k;
    } else {
      proveedor = '${_proveedores.length} proveedores';
    }

    return '$vendedor · $proveedor';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ventasProvider = context.watch<VentasProvider>();
    final productosProvider = context.watch<ProductosProvider>();

    final ventas = ventasProvider.ventasUnificado;
    final miId = context.read<AuthProvider>().usuario?.id;
    final proveedorPorProducto =
        ProductosVendidosAgregacion.proveedorPorProducto(
          productosProvider.allProductos,
        );

    final filtradas = ProductosVendidosAgregacion.ventasFiltradas(
      ventas,
      _vendedores,
      miId,
    );
    final resumen = ProductosVendidosAgregacion.resumen(
      filtradas,
      proveedorPorProducto,
      _proveedores,
    );

    final agrupados = _vista == VistaProductosVendidos.agrupada
        ? ProductosVendidosAgregacion.agrupados(
            filtradas,
            proveedorPorProducto,
            _proveedores,
            orden: _orden,
          )
        : const <ProductoVendidoAgrupado>[];
    final historicos = _vista == VistaProductosVendidos.historica
        ? ProductosVendidosAgregacion.historicos(
            filtradas,
            proveedorPorProducto,
            _proveedores,
          )
        : const <ProductoVendidoItem>[];

    final vacia = _vista == VistaProductosVendidos.agrupada
        ? agrupados.isEmpty
        : historicos.isEmpty;
    final precioMedio =
        _vista == VistaProductosVendidos.agrupada &&
        agrupados.any((p) => p.preciosDistintos);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos vendidos'),
        actions: [
          IconButton(
            onPressed: () => _abrirFiltros(ventas, proveedorPorProducto),
            tooltip: 'Filtros',
            icon: BadgedIcon(
              pendingCount: _filtrosActivos,
              semanticsLabel: _filtrosActivos > 0
                  ? '$_filtrosActivos filtro${_filtrosActivos == 1 ? '' : 's'} activo${_filtrosActivos == 1 ? '' : 's'}'
                  : null,
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
      body: ventasProvider.isLoadingVentas && ventas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                await _resolveTransferNames();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _AlcanceHeader(
                      background: colors.page,
                      extent:
                          MediaQuery.textScalerOf(context).scale(13) * 2.4 + 20,
                      child: _buildAlcance(
                        _opcionesVendedor(ventas),
                        () => _abrirFiltros(ventas, proveedorPorProducto),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildResumen(resumen)),
                  SliverToBoxAdapter(child: _buildControles()),
                  if (vacia)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmpty(ventas.isEmpty),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppRadius.md),
                          ),
                          child: DataTableHeader(
                            columns: _columnas(precioMedio: precioMedio),
                          ),
                        ),
                      ),
                    ),
                    _vista == VistaProductosVendidos.agrupada
                        ? _buildFilasAgrupadas(agrupados, precioMedio)
                        : _buildFilasHistoricas(historicos),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ],
              ),
            ),
    );
  }

  /// La columna de precio se rotula "P. medio" en cuanto algún producto de la
  /// lista se vendió a más de un precio: llamarla "Precio" ahí invitaría a
  /// multiplicarla por la cantidad y no cuadraría con el total.
  List<TableColumn> _columnas({bool precioMedio = false}) {
    return [
      const TableColumn('Cant.', width: 56, align: TableAlign.end),
      TableColumn(
        precioMedio ? 'P. medio' : 'Precio',
        flex: 1,
        align: TableAlign.end,
      ),
      const TableColumn('Total', width: 104, align: TableAlign.end),
    ];
  }

  // ── Alcance ────────────────────────────────────────────────────────────────

  Widget _buildAlcance(Map<String, String> opciones, VoidCallback onCambiar) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _textoAlcance(opciones),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium!.copyWith(color: colors.textSecondary),
            ),
          ),
          TextButton(onPressed: onCambiar, child: const Text('Cambiar')),
        ],
      ),
    );
  }

  // ── Resumen ────────────────────────────────────────────────────────────────

  Widget _buildResumen(ResumenVendido r) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total vendido', style: text.bodyLarge),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        Formatters.formatCurrency(r.totalVendido),
                        style: tabularNums(
                          text.titleLarge!.copyWith(color: colors.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${Formatters.formatCantidad(r.unidades)} '
                '${r.unidades == 1 ? 'unidad' : 'unidades'} · '
                '${r.productosDistintos} '
                '${r.productosDistintos == 1 ? 'producto' : 'productos'}',
                style: text.bodySmall!.copyWith(color: colors.textSecondary),
              ),
              if (r.desglosePagoDisponible) ...[
                const Divider(height: 20),
                _FilaTotal(label: 'Efectivo', valor: r.efectivo),
                _FilaTotal(label: 'Transferencia', valor: r.transferencia),
                if (r.descuentos > 0)
                  _FilaTotal(label: 'Descuentos', valor: -r.descuentos),
                ...r.transferenciaPorDestino.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: _FilaTotal(
                      label: e.key == kSinDestino
                          ? '· Sin destino'
                          : '· ${_destinos[e.key] ?? e.key}',
                      valor: e.value,
                      secundaria: true,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                _Nota(
                  icon: Icons.info_outline,
                  tone: colors.textSecondary,
                  texto:
                      'Con un filtro de proveedor activo no se puede repartir '
                      'el pago: cada venta puede mezclar proveedores.',
                ),
              ],
              if (r.ventasConError > 0 || r.ventasSinSubir > 0) ...[
                const SizedBox(height: 10),
                _Nota(
                  icon: Icons.cloud_off,
                  tone: r.ventasConError > 0 ? colors.negative : colors.caution,
                  texto:
                      '${[if (r.ventasConError > 0) '${r.ventasConError} venta${r.ventasConError == 1 ? '' : 's'} con error', if (r.ventasSinSubir > 0) '${r.ventasSinSubir} venta${r.ventasSinSubir == 1 ? '' : 's'} sin subir'].join(' · ')} están incluidas en estos totales.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Controles de vista y orden ─────────────────────────────────────────────

  Widget _buildControles() {
    // `Wrap` y no `Row`: con la letra del sistema ampliada los dos chips y el
    // selector de orden no caben en una línea, y pasar a dos es mejor que
    // esconder la mitad en un scroll horizontal.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AppChoiceChip(
            label: 'Agrupada',
            selected: _vista == VistaProductosVendidos.agrupada,
            onTap: () =>
                setState(() => _vista = VistaProductosVendidos.agrupada),
          ),
          AppChoiceChip(
            label: 'Histórica',
            selected: _vista == VistaProductosVendidos.historica,
            onTap: () =>
                setState(() => _vista = VistaProductosVendidos.historica),
          ),
          if (_vista == VistaProductosVendidos.agrupada)
            PopupMenuButton<OrdenProductosVendidos>(
              tooltip: 'Ordenar',
              initialValue: _orden,
              onSelected: (o) => setState(() => _orden = o),
              itemBuilder: (_) => [
                for (final o in OrdenProductosVendidos.values)
                  PopupMenuItem(value: o, child: Text(o.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _orden.label,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: context.colors.accent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Filas ──────────────────────────────────────────────────────────────────

  Widget _buildFilasAgrupadas(
    List<ProductoVendidoAgrupado> items,
    bool precioMedio,
  ) {
    final columnas = _columnas(precioMedio: precioMedio);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final p = items[i];
          final cantidad = Formatters.formatCantidad(p.cantidad);
          return _EnvoltorioFila(
            primera: i == 0,
            ultima: i == items.length - 1,
            child: DataTableRow(
              columns: columnas,
              title: _NombreProducto(nombre: p.nombre, proveedor: p.proveedor),
              semanticsLabel:
                  '${p.nombre}. $cantidad unidades. '
                  'Total ${Formatters.formatCurrency(p.total)}.',
              cells: [
                _Cifra(cantidad),
                _Cifra(
                  Formatters.formatCurrency(p.precioUnitario),
                  // Cuando el producto se vendió a varios precios, este es un
                  // promedio: decirlo evita que el cajero lo lea como "el
                  // precio" y no le cuadre con el total.
                  sufijo: p.preciosDistintos ? 'medio' : null,
                ),
                _Cifra(Formatters.formatCurrency(p.total), destacada: true),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilasHistoricas(List<ProductoVendidoItem> items) {
    final columnas = _columnas();
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final p = items[i];
          final fecha = DateTime.fromMillisecondsSinceEpoch(p.ventaCreatedAtMs);
          final cantidad = Formatters.formatCantidad(p.cantidad);
          return _EnvoltorioFila(
            primera: i == 0,
            ultima: i == items.length - 1,
            child: DataTableRow(
              columns: columnas,
              title: _NombreProducto(nombre: p.nombre, proveedor: p.proveedor),
              semanticsLabel:
                  '${p.nombre}. $cantidad unidades. '
                  'Total ${Formatters.formatCurrency(p.total)}. '
                  '${Formatters.formatDateTime(fecha)}. '
                  '${SyncStateLabels.label(p.syncState)}.',
              cells: [
                _Cifra(cantidad),
                _Cifra(Formatters.formatCurrency(p.precio)),
                _Cifra(Formatters.formatCurrency(p.total), destacada: true),
              ],
              footer: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      Formatters.formatDateTime(fecha),
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall!.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SyncStateChip(p.syncState, showIcon: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(bool periodoVacio) {
    if (periodoVacio) {
      return const EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'Todavía no hay ventas en este período',
        message: 'Lo que vendas aparecerá aquí, agrupado por producto.',
      );
    }
    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: 'Ningún producto con estos filtros',
      message: _textoAlcance(const {}),
      action: OutlinedButton(
        onPressed: () => setState(() {
          _vendedores = {kFiltroTodos};
          _proveedores = {kFiltroTodos};
        }),
        child: const Text('Quitar filtros'),
      ),
    );
  }

  // ── Hoja de filtros ────────────────────────────────────────────────────────

  Future<void> _abrirFiltros(
    List<VentaUnificadaModel> ventas,
    Map<String, String?> proveedorPorProducto,
  ) async {
    final resultado = await showModalBottomSheet<(Set<String>, Set<String>)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FiltrosSheet(
        vendedores: _vendedores,
        proveedores: _proveedores,
        opcionesVendedor: _opcionesVendedor(ventas),
        opcionesProveedor: _opcionesProveedor(ventas, proveedorPorProducto),
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      _vendedores = resultado.$1;
      _proveedores = resultado.$2;
    });
  }
}

// ── Widgets de apoyo ─────────────────────────────────────────────────────────

/// Da a las filas el marco que antes ponía la `Card`: fondo, borde y esquinas
/// redondeadas sólo en los extremos. Va fila a fila porque la lista es un
/// `SliverList` —una tabla de cientos de filas no puede construirse entera
/// dentro de una tarjeta.
class _EnvoltorioFila extends StatelessWidget {
  final bool primera;
  final bool ultima;
  final Widget child;

  const _EnvoltorioFila({
    required this.primera,
    required this.ultima,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radio = Radius.circular(AppRadius.md);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.raised,
        border: Border(
          left: BorderSide(color: colors.border),
          right: BorderSide(color: colors.border),
          bottom: BorderSide(color: colors.border),
        ),
        borderRadius: BorderRadius.vertical(
          bottom: ultima ? radio : Radius.zero,
        ),
      ),
      child: Column(children: [if (!primera) const Divider(height: 1), child]),
    );
  }
}

class _NombreProducto extends StatelessWidget {
  final String nombre;
  final String? proveedor;

  const _NombreProducto({required this.nombre, this.proveedor});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          nombre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium,
        ),
        if (proveedor != null && proveedor!.isNotEmpty)
          Text(
            proveedor!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall!.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

/// Una cifra de tabla: `tabularNums` y encogible, para que un importe largo se
/// achique en vez de desbordar cuando la letra del sistema está ampliada.
class _Cifra extends StatelessWidget {
  final String valor;
  final bool destacada;
  final String? sufijo;

  const _Cifra(this.valor, {this.destacada = false, this.sufijo});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final estilo = destacada
        ? text.titleMedium!
        : text.bodyMedium!.copyWith(color: colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(valor, style: tabularNums(estilo)),
        ),
        if (sufijo != null)
          Text(
            sufijo!,
            style: text.labelSmall!.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

class _FilaTotal extends StatelessWidget {
  final String label;
  final double valor;
  final bool secundaria;

  const _FilaTotal({
    required this.label,
    required this.valor,
    this.secundaria = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final estilo = secundaria
        ? text.bodyMedium!.copyWith(color: colors.textSecondary)
        : text.bodyLarge!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis, style: estilo),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.formatCurrency(valor),
                style: tabularNums(
                  estilo.copyWith(
                    fontWeight: secundaria ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String texto;

  const _Nota({required this.icon, required this.tone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: tone),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: tone),
          ),
        ),
      ],
    );
  }
}

/// Cabecera pegajosa con el alcance de los datos.
///
/// Es la respuesta al problema de fondo de esta pantalla: el filtro de vendedor
/// arranca acotado a las ventas propias y antes no había forma de saberlo, así
/// que "Total vendido" se leía como el total de la tienda.
class _AlcanceHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;
  final Color background;

  const _AlcanceHeader({
    required this.child,
    required this.extent,
    required this.background,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background,
      height: extent,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_AlcanceHeader old) =>
      old.child != child ||
      old.extent != extent ||
      old.background != background;
}

/// Hoja de filtros. Saca del cuerpo de la pantalla los ~300px de chips que
/// dejaban la primera fila de datos por debajo del pliegue.
class _FiltrosSheet extends StatefulWidget {
  final Set<String> vendedores;
  final Set<String> proveedores;
  final Map<String, String> opcionesVendedor;
  final List<String> opcionesProveedor;

  const _FiltrosSheet({
    required this.vendedores,
    required this.proveedores,
    required this.opcionesVendedor,
    required this.opcionesProveedor,
  });

  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  late Set<String> _vendedores = {...widget.vendedores};
  late Set<String> _proveedores = {...widget.proveedores};

  /// Alterna una opción dentro de un filtro que tiene un "Todos" exclusivo:
  /// elegir cualquier otra lo apaga, y quedarse sin ninguna vuelve a "Todos".
  Set<String> _alternar(Set<String> actual, String key) {
    if (key == kFiltroTodos) return {kFiltroTodos};
    final next = {...actual}..remove(kFiltroTodos);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    return next.isEmpty ? {kFiltroTodos} : next;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Filtros', style: text.titleLarge)),
                  TextButton(
                    onPressed: () => setState(() {
                      _vendedores = {kFiltroTodos};
                      _proveedores = {kFiltroTodos};
                    }),
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vendido por', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppFilterChip(
                          label: 'Todos',
                          selected:
                              _vendedores.contains(kFiltroTodos) ||
                              _vendedores.isEmpty,
                          onTap: () =>
                              setState(() => _vendedores = {kFiltroTodos}),
                        ),
                        ...widget.opcionesVendedor.entries.map(
                          (e) => AppFilterChip(
                            label: e.value,
                            selected: _vendedores.contains(e.key),
                            onTap: () => setState(
                              () => _vendedores = _alternar(_vendedores, e.key),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Proveedor', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.opcionesProveedor.map((key) {
                        final label = switch (key) {
                          kFiltroTodos => 'Todos',
                          kFiltroPropios => 'Productos propios',
                          _ => key,
                        };
                        return AppFilterChip(
                          label: label,
                          selected: _proveedores.contains(key),
                          onTap: () => setState(
                            () => _proveedores = _alternar(_proveedores, key),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppTapTarget.min),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, (_vendedores, _proveedores)),
                  child: const Text('Aplicar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
