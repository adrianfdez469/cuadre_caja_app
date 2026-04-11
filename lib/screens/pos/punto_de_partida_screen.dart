import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/di/injection.dart';
import '../../data/datasources/remote/resumen_dia_remote_datasource.dart';
import '../../data/models/resumen_dia_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/periodo_provider.dart';

class PuntoDePartidaScreen extends StatefulWidget {
  const PuntoDePartidaScreen({super.key});

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
    _datasource = ResumenDiaRemoteDataSource(injection.apiClient);
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

      setState(() {
        if (fetchTodos) {
          _resumenTodos = result;
        } else {
          _resumenConMovimientos = result;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = _parseError(e);
      });
    }
  }

  String _parseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('handshake') ||
        msg.contains('timeout')) {
      return 'Sin conexión a internet. Revisa tu WiFi o datos móviles.';
    }
    if (msg.contains('400')) return 'El período activo no está disponible.';
    if (msg.contains('401')) return 'Sesión expirada. Reinicia la app.';
    if (msg.contains('404')) return 'No se encontró el período de caja.';
    return 'Error al cargar datos. Intenta de nuevo.';
  }

  Future<void> _onToggleVisibilidad() async {
    if (!_mostrarTodos) {
      // Abriendo ojo: necesitamos datos completos
      if (_resumenTodos == null) {
        setState(() => _mostrarTodos = true);
        await _fetchData(soloConMovimientos: false);
      } else {
        setState(() => _mostrarTodos = true);
      }
    } else {
      setState(() => _mostrarTodos = false);
    }
  }

  Future<void> _onRefresh() async {
    // No limpiamos los datos previos antes del fetch para que, si falla
    // (p.ej. sin conexión), el usuario siga viendo el contenido anterior.
    if (_mostrarTodos) {
      await _fetchData(soloConMovimientos: false);
    } else {
      await _fetchData(soloConMovimientos: true);
    }
  }

  ResumenDiaModel? get _resumenActual =>
      _mostrarTodos ? _resumenTodos : _resumenConMovimientos;

  List<ResumenDiaProducto> get _productosFiltrados {
    final resumen = _resumenActual;
    if (resumen == null) return [];

    final query = _normalizar(_searchQuery);
    if (query.isEmpty) return resumen.productos;

    return resumen.productos
        .where((p) => _normalizar(p.nombre).contains(query))
        .toList();
  }

  String _normalizar(String texto) {
    const withAccents = 'áéíóúàèìòùâêîôûäëïöüÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÄËÏÖÜñÑ';
    const withoutAccents = 'aeiouaeiouaeiouaeiouAEIOUAEIOUAEIOUAEIOUnn';

    var result = texto.toLowerCase();
    for (var i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result;
  }

  Map<String, List<ResumenDiaProducto>> _agruparPorCategoria(
    List<ResumenDiaProducto> productos,
  ) {
    final Map<String, List<ResumenDiaProducto>> grupos = {};
    for (final p in productos) {
      final cat = p.categoriaNombre ?? 'Sin categoría';
      grupos.putIfAbsent(cat, () => []).add(p);
    }

    // Ordenar productos dentro de cada grupo por ultimaModificacion desc
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

    // Retornar ordenado por nombre de categoría
    final sortedKeys = grupos.keys.toList()..sort();
    return {for (final k in sortedKeys) k: grupos[k]!};
  }

  Color _parseCategoriaColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.primary;
    try {
      return Color(int.parse(hex.replaceAll('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Color _colorExistencia(double cantidad) {
    if (cantidad <= 0) return Colors.red;
    if (cantidad <= 5) return Colors.orange;
    return Colors.green;
  }

  String _formatNum(double value, bool permiteDecimal) {
    if (permiteDecimal) return value.toStringAsFixed(2);
    return value.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  _buildContent(),
                  if (_isLoading) _buildLoadingOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Punto de partida y comportamiento',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : _onRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null && _resumenActual == null) {
      return _buildError();
    }

    return Column(
      children: [
        // Banner de error cuando hay datos previos pero el refresh falló
        if (_error != null && _resumenActual != null)
          _buildErrorBanner(_error!),
        if (_resumenActual != null) _buildTotalesRow(_resumenActual!.totales),
        _buildFiltrosRow(),
        Expanded(child: _buildLista()),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(Icons.close, size: 16, color: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalesRow(ResumenDiaTotales totales) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _TotalCard(
              icono: Icons.shopping_cart,
              label: 'Ventas',
              valor: totales.ventas,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TotalCard(
              icono: Icons.trending_up,
              label: 'Entradas',
              valor: totales.entradas,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TotalCard(
              icono: Icons.trending_down,
              label: 'Salidas',
              valor: totales.salidas,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar producto...',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _mostrarTodos ? Icons.visibility : Icons.visibility_off,
              color: _mostrarTodos ? AppColors.primary : Colors.grey,
            ),
            tooltip: _mostrarTodos
                ? 'Mostrando todos los productos'
                : 'Mostrando solo con movimientos',
            onPressed: _isLoading ? null : _onToggleVisibilidad,
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    final productos = _productosFiltrados;

    if (productos.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No hay productos para mostrar',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final grupos = _agruparPorCategoria(productos);
    final categorias = grupos.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: categorias.length,
      itemBuilder: (context, i) {
        final cat = categorias[i];
        final items = grupos[cat]!;
        final colorHex = items.first.categoriaColor;
        final catColor = _parseCategoriaColor(colorHex);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: catColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: catColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            ...items.map((p) => _ProductoCard(
                  producto: p,
                  colorExistencia: _colorExistencia(p.cantidadFinal),
                  formatNum: _formatNum,
                )),
          ],
        );
      },
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.white.withValues(alpha: 0.6),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              onPressed: _onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Widgets internos
// ──────────────────────────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final IconData icono;
  final String label;
  final double valor;
  final Color color;

  const _TotalCard({
    required this.icono,
    required this.label,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            valor % 1 == 0 ? valor.toInt().toString() : valor.toStringAsFixed(1),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductoCard extends StatelessWidget {
  final ResumenDiaProducto producto;
  final Color colorExistencia;
  final String Function(double, bool) formatNum;

  const _ProductoCard({
    required this.producto,
    required this.colorExistencia,
    required this.formatNum,
  });

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final fmt = formatNum;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.nombre,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InfoBox(
                  label: 'Inicial',
                  valor: fmt(p.cantidadInicial, p.permiteDecimal),
                  backgroundColor: Colors.grey.shade100,
                  textColor: Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoBox(
                  label: 'Existencia actual',
                  valor: fmt(p.cantidadFinal, p.permiteDecimal),
                  backgroundColor: colorExistencia.withValues(alpha: 0.12),
                  textColor: colorExistencia,
                  bold: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'MOVIMIENTOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _MovimientoBox(
                  label: 'Ventas',
                  valor: fmt(p.ventas, p.permiteDecimal),
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MovimientoBox(
                  label: 'Entradas',
                  valor: fmt(p.entradas, p.permiteDecimal),
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MovimientoBox(
                  label: 'Salidas',
                  valor: fmt(p.salidas, p.permiteDecimal),
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label;
  final String valor;
  final Color backgroundColor;
  final Color textColor;
  final bool bold;

  const _InfoBox({
    required this.label,
    required this.valor,
    required this.backgroundColor,
    required this.textColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: 18,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovimientoBox extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;

  const _MovimientoBox({
    required this.label,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
