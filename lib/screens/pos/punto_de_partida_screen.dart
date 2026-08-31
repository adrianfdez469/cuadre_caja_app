import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/di/injection.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/search_text.dart';
import '../../data/datasources/remote/resumen_dia_remote_datasource.dart';
import '../../data/models/resumen_dia_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../widgets/app_filter_chip.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/stat_tile.dart';

class PuntoDePartidaScreen extends StatefulWidget {
  /// Sólo para tests: en la app real se construye sobre `injection.apiClient`.
  /// Sin esta costura la pantalla no se puede montar en un widget test, porque
  /// pediría el resumen a la red en su `initState`.
  final ResumenDiaRemoteDataSource? datasource;

  const PuntoDePartidaScreen({super.key, this.datasource});

  @override
  State<PuntoDePartidaScreen> createState() => _PuntoDePartidaScreenState();
}

class _PuntoDePartidaScreenState extends State<PuntoDePartidaScreen> {
  late final ResumenDiaRemoteDataSource _datasource;

  // Datos cargados desde la API
  ResumenDiaModel? _resumenConMovimientos;
  ResumenDiaModel? _resumenTodos;

  bool _isLoading = false;
  String? _error;

  // Filtros
  bool _mostrarTodos = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _datasource =
        widget.datasource ?? ResumenDiaRemoteDataSource(injection.apiClient);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData({bool? soloConMovimientos}) async {
    final auth = context.read<AuthProvider>();
    final periodo = context.read<PeriodoProvider>();

    if (auth.tiendaId.isEmpty || periodo.periodoId == null) return;

    final fetchTodos = soloConMovimientos == null
        ? _mostrarTodos
        : !soloConMovimientos;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _datasource.getResumenDia(
        tiendaId: auth.tiendaId,
        cierreId: periodo.periodoId!,
        soloConMovimientos: !fetchTodos,
      );
      if (!mounted) return;
      setState(() {
        if (fetchTodos) {
          _resumenTodos = result;
        } else {
          _resumenConMovimientos = result;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _mensajeDeError(e);
      });
    }
  }

  /// Traduce el fallo a algo accionable.
  ///
  /// Antes se adivinaba buscando subcadenas dentro de `e.toString()`, que
  /// dependía del texto de la excepción: aquí se mira el tipo real que lanza
  /// el cliente HTTP.
  String _mensajeDeError(Object e) {
    if (e is! DioException) return 'Error al cargar datos. Inténtalo de nuevo.';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'La conexión tardó demasiado. Inténtalo de nuevo.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Sin conexión a internet. Revisa tu WiFi o datos móviles.';
      case DioExceptionType.badCertificate:
        return 'No se pudo verificar la conexión con el servidor.';
      case DioExceptionType.cancel:
        return 'La consulta se canceló.';
      case DioExceptionType.badResponse:
        return switch (e.response?.statusCode) {
          400 => 'El período activo no está disponible.',
          401 => 'Sesión expirada. Reinicia la app.',
          403 => 'No tienes permiso para ver este resumen.',
          404 => 'No se encontró el período de caja.',
          final code => 'El servidor respondió con un error ($code).',
        };
    }
  }

  Future<void> _setMostrarTodos(bool todos) async {
    // Los dos universos de datos son consultas distintas al servidor: al abrir
    // "Todos" por primera vez hay que pedirlo, después ya está en memoria.
    final hayQuePedir = todos && _resumenTodos == null;
    setState(() => _mostrarTodos = todos);
    if (hayQuePedir) await _fetchData(soloConMovimientos: false);
  }

  Future<void> _onRefresh() async {
    // No se limpian los datos previos antes del fetch: si falla (p.ej. sin
    // conexión) el usuario sigue viendo el contenido anterior con un aviso.
    await _fetchData(soloConMovimientos: !_mostrarTodos);
  }

  ResumenDiaModel? get _resumenActual =>
      _mostrarTodos ? _resumenTodos : _resumenConMovimientos;

  List<ResumenDiaProducto> get _productosFiltrados {
    final resumen = _resumenActual;
    if (resumen == null) return const [];

    final query = SearchText.normalize(_searchQuery);
    if (query.isEmpty) return resumen.productos;

    return resumen.productos
        .where((p) => SearchText.normalize(p.nombre).contains(query))
        .toList();
  }

  Map<String, List<ResumenDiaProducto>> _agruparPorCategoria(
    List<ResumenDiaProducto> productos,
  ) {
    final grupos = <String, List<ResumenDiaProducto>>{};
    for (final p in productos) {
      grupos.putIfAbsent(p.categoriaNombre ?? 'Sin categoría', () => []).add(p);
    }
    for (final key in grupos.keys) {
      grupos[key]!.sort((a, b) {
        if (a.ultimaModificacion == null && b.ultimaModificacion == null) {
          return 0;
        }
        if (a.ultimaModificacion == null) return 1;
        if (b.ultimaModificacion == null) return -1;
        return b.ultimaModificacion!.compareTo(a.ultimaModificacion!);
      });
    }
    final sortedKeys = grupos.keys.toList()..sort();
    return {for (final k in sortedKeys) k: grupos[k]!};
  }

  Color _colorCategoria(String? hex) {
    if (hex == null || hex.isEmpty) return context.colors.accent;
    try {
      return Color(int.parse(hex.replaceAll('#', '0xFF')));
    } catch (_) {
      return context.colors.accent;
    }
  }

  /// Tono de la existencia final. Es la única cifra de la pantalla que sí es
  /// buena o mala: cero es un problema, poco es un aviso.
  StatTone _tonoExistencia(double cantidad) {
    if (cantidad <= 0) return StatTone.negative;
    if (cantidad <= 5) return StatTone.caution;
    return StatTone.positive;
  }

  @override
  Widget build(BuildContext context) {
    final resumen = _resumenActual;
    final productos = _productosFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Punto de partida'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : _onRefresh,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null && resumen == null)
            _buildError()
          else
            RefreshIndicator(
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_error != null)
                    SliverToBoxAdapter(child: _buildBannerError(_error!)),
                  if (resumen != null)
                    SliverToBoxAdapter(child: _buildTotales(resumen.totales)),
                  SliverToBoxAdapter(child: _buildControles()),
                  if (productos.isEmpty && !_isLoading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmpty(),
                    )
                  else
                    _buildLista(productos),
                ],
              ),
            ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildBannerError(String message) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colors.cautionWash,
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 16, color: colors.caution),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$message Se muestran los últimos datos cargados.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: colors.caution),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: colors.caution,
            tooltip: 'Descartar aviso',
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Widget _buildTotales(ResumenDiaTotales totales) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              icon: Icons.shopping_cart_outlined,
              label: 'Ventas',
              // Vender no es negativo: el rojo se reserva para lo que exige
              // atención. Ventas y salidas son movimiento de stock, no pérdida.
              tone: StatTone.info,
              centered: true,
              value: Formatters.formatCantidad(totales.ventas),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              icon: Icons.trending_up,
              label: 'Entradas',
              tone: StatTone.positive,
              centered: true,
              value: Formatters.formatCantidad(totales.entradas),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              icon: Icons.trending_down,
              label: 'Salidas',
              tone: StatTone.info,
              centered: true,
              value: Formatters.formatCantidad(totales.salidas),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControles() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar producto…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 10),
          // Antes esto era un icono de ojo: el control que decide qué universo
          // de productos se está viendo, sin más pista que su tooltip.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              AppChoiceChip(
                label: 'Con movimientos',
                selected: !_mostrarTodos,
                onTap: _isLoading ? () {} : () => _setMostrarTodos(false),
              ),
              AppChoiceChip(
                label: 'Todos',
                selected: _mostrarTodos,
                onTap: _isLoading ? () {} : () => _setMostrarTodos(true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    if (_searchQuery.isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Sin coincidencias',
        message: 'Ningún producto contiene "$_searchQuery".',
        action: OutlinedButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
          child: const Text('Limpiar búsqueda'),
        ),
      );
    }
    if (!_mostrarTodos) {
      return EmptyState(
        icon: Icons.bar_chart,
        title: 'Todavía no hay movimientos',
        message: 'Ningún producto se movió en este período.',
        action: OutlinedButton(
          onPressed: () => _setMostrarTodos(true),
          child: const Text('Ver todos los productos'),
        ),
      );
    }
    return const EmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No hay productos para mostrar',
    );
  }

  Widget _buildLista(List<ResumenDiaProducto> productos) {
    final grupos = _agruparPorCategoria(productos);

    // Se aplana en encabezados y productos para que el `SliverList` siga
    // construyendo sólo lo visible: con "Todos" activo esto es el inventario
    // entero.
    final filas = <Object>[];
    grupos.forEach((categoria, items) {
      filas.add(
        _Categoria(
          nombre: categoria,
          color: _colorCategoria(items.first.categoriaColor),
        ),
      );
      filas.addAll(items);
    });

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      sliver: SliverList.builder(
        itemCount: filas.length,
        itemBuilder: (context, i) {
          final fila = filas[i];
          if (fila is _Categoria) return _EncabezadoCategoria(categoria: fila);
          final p = fila as ResumenDiaProducto;
          return _ProductoFila(
            producto: p,
            tonoExistencia: _tonoExistencia(p.cantidadFinal),
          );
        },
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: context.colors.raised.withValues(alpha: 0.6),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Widget _buildError() {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'No se pudo cargar el resumen',
      message: _error,
      action: ElevatedButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar'),
        onPressed: _onRefresh,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Widgets internos
// ──────────────────────────────────────────────────────────────────────────────

class _Categoria {
  final String nombre;
  final Color color;

  const _Categoria({required this.nombre, required this.color});
}

class _EncabezadoCategoria extends StatelessWidget {
  final _Categoria categoria;

  const _EncabezadoCategoria({required this.categoria});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          // El color viene del servidor y no hay forma de garantizar su
          // contraste, así que va en un punto y no en el texto: el rótulo usa
          // un color del tema y siempre se lee.
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: categoria.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              categoria.nombre.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: context.colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila de producto: nombre, resumen de movimientos y existencia actual.
///
/// Antes cada producto era una tarjeta de unos 150px con cinco cifras en cajas.
/// Con el inventario completo eso hacía imposible comparar dos productos sin
/// memorizar, así que la fila se queda con lo que se compara —la existencia— y
/// el desglose completo aparece al tocarla.
class _ProductoFila extends StatefulWidget {
  final ResumenDiaProducto producto;
  final StatTone tonoExistencia;

  const _ProductoFila({required this.producto, required this.tonoExistencia});

  @override
  State<_ProductoFila> createState() => _ProductoFilaState();
}

class _ProductoFilaState extends State<_ProductoFila> {
  bool _abierta = false;

  String _num(double v) => Formatters.formatCantidad(
    v,
    permiteDecimal: widget.producto.permiteDecimal,
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    // Sólo se nombran los movimientos que existen: un "Entradas 0" no dice
    // nada y empuja fuera de la línea lo que sí importa.
    final partes = [
      'Inicial ${_num(p.cantidadInicial)}',
      if (p.ventas != 0) 'Ventas ${_num(p.ventas)}',
      if (p.entradas != 0) 'Entradas ${_num(p.entradas)}',
      if (p.salidas != 0) 'Salidas ${_num(p.salidas)}',
    ].join(' · ');

    return Semantics(
      button: true,
      label:
          '${p.nombre}. Existencia actual ${_num(p.cantidadFinal)}. $partes.',
      container: true,
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => setState(() => _abierta = !_abierta),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                          if (p.proveedorNombre != null &&
                              p.proveedorNombre!.isNotEmpty)
                            Text(
                              p.proveedorNombre!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall!.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            partes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tabularNums(
                              text.bodySmall!.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 92,
                      child: StatTile(
                        label: 'Actual',
                        value: _num(p.cantidadFinal),
                        tone: widget.tonoExistencia,
                        centered: true,
                      ),
                    ),
                  ],
                ),
                if (_abierta) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Inicial',
                          value: _num(p.cantidadInicial),
                          tone: StatTone.neutral,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: StatTile(
                          label: 'Ventas',
                          value: _num(p.ventas),
                          tone: StatTone.info,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: StatTile(
                          label: 'Entradas',
                          value: _num(p.entradas),
                          tone: StatTone.positive,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: StatTile(
                          label: 'Salidas',
                          value: _num(p.salidas),
                          tone: StatTone.info,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
