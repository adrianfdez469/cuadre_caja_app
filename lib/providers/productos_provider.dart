import 'package:flutter/foundation.dart';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import '../core/utils/producto_pos_rules.dart';
import '../core/utils/search_text.dart';
import '../data/models/producto_model.dart';
import '../data/models/categoria_model.dart';
import '../services/sync_service.dart';

/// Texto buscable de un producto, ya normalizado.
///
/// Se precalcula al cargar el catálogo en vez de en cada pulsación: normalizar
/// N productos por cada tecla es justo lo que vuelve lenta una búsqueda
/// incremental.
class _SearchEntry {
  /// Nombre tal como se muestra en el catálogo ("nombre - proveedor"),
  /// normalizado. Es sobre este texto sobre el que se calcula la relevancia:
  /// el cajero ordena mentalmente por lo que ve.
  final String nombre;

  /// Todo lo buscable junto: nombre, proveedor, descripción y códigos.
  final String haystack;

  const _SearchEntry({required this.nombre, required this.haystack});
}

class ProductosProvider extends ChangeNotifier {
  final SyncService _syncService;

  List<ProductoModel> _rawProductos = [];
  List<ProductoModel> _allProductos = [];
  List<ProductoModel> _filteredProductos = [];
  List<CategoriaModel> _categorias = [];
  bool _isLoading = false;
  String? _selectedCategoriaId;
  bool _permitirSinStock = false;

  /// Consulta activa del buscador. Vive en el provider (y no solo en el
  /// `TextField`) para que categoría y búsqueda se apliquen **siempre juntas**:
  /// antes, tocar una categoría descartaba la búsqueda pero dejaba el texto
  /// escrito en pantalla.
  String _query = '';

  /// Índice de búsqueda por `producto.id`.
  Map<String, _SearchEntry> _searchIndex = {};

  ProductosProvider(this._syncService);

  List<ProductoModel> get productos => _filteredProductos;
  List<ProductoModel> get allProductos => _allProductos;
  List<CategoriaModel> get categorias => _categorias;
  bool get isLoading => _isLoading;
  String? get selectedCategoriaId => _selectedCategoriaId;
  bool get permitirSinStock => _permitirSinStock;
  String get query => _query;

  /// Re-aplica el filtro de catálogo según si se permite vender sin existencias
  /// (sin conexión, o con el ajuste "Vender sin existencias" activo): los
  /// productos agotados solo se listan cuando se permite. Ver `VentaSinStockPolicy`.
  void applyStockFilter(bool permitirSinStock) {
    if (_permitirSinStock == permitirSinStock) return;
    _permitirSinStock = permitirSinStock;
    _rebuildProductLists();
    notifyListeners();
  }

  void _rebuildProductLists() {
    _allProductos = ProductoPosRules.filtrarYOrdenarParaPos(
      _rawProductos,
      permitirSinStock: _permitirSinStock,
    );
    // Conserva la búsqueda activa: antes, cualquier reconstrucción (una venta,
    // un cambio de stock) devolvía la lista completa por debajo del cajero.
    _applyFilters();
  }

  /// Recalcula el texto buscable de cada producto. Solo hace falta donde cambia
  /// el **contenido** del catálogo (carga y asociación de códigos), no donde
  /// solo cambian existencias: `updateExistenciaLocal` y `applyStockFilter`
  /// crean modelos nuevos pero con el mismo `id` y los mismos campos buscables.
  void _rebuildSearchIndex() {
    _searchIndex = {
      for (final p in _rawProductos)
        p.id: _SearchEntry(
          nombre: SearchText.normalize(ProductoPosRules.nombreParaMostrar(p)),
          haystack: SearchText.normalize([
            // nombreParaMostrar ya incluye el proveedor, que se ve en la fila
            // del catálogo y hasta ahora no se podía buscar.
            ProductoPosRules.nombreParaMostrar(p),
            p.descripcion ?? '',
            ...p.codigos.map((c) => c.codigo),
          ].join(' ')),
        ),
    };
  }

  /// Aplica a la vez los dos criterios de filtrado: categoría y búsqueda.
  ///
  /// Es el único sitio que escribe `_filteredProductos`. Tenerlo centralizado
  /// es lo que impide que vuelvan a divergir (antes `filterByCategoria`
  /// ignoraba la consulta activa y `searchProductos` sí respetaba la categoría).
  void _applyFilters() {
    var resultado = _selectedCategoriaId == null
        ? List<ProductoModel>.from(_allProductos)
        : _allProductos
            .where((p) => p.categoriaId == _selectedCategoriaId)
            .toList();

    final tokens = SearchText.tokens(_query);
    if (tokens.isEmpty) {
      // Sin búsqueda se respeta el alfabético de filtrarYOrdenarParaPos.
      _filteredProductos = resultado;
      return;
    }

    resultado = resultado
        .where((p) =>
            SearchText.matchesAll(_searchIndex[p.id]?.haystack ?? '', tokens))
        .toList();

    final consulta = SearchText.normalize(_query);
    resultado.sort((a, b) {
      final ea = _searchIndex[a.id];
      final eb = _searchIndex[b.id];
      final rangoA = _rangoRelevancia(ea, consulta, tokens.first);
      final rangoB = _rangoRelevancia(eb, consulta, tokens.first);
      if (rangoA != rangoB) return rangoA.compareTo(rangoB);
      // `List.sort` no es estable: sin este desempate el orden dentro de un
      // mismo rango sería impredecible.
      return (ea?.nombre ?? '').compareTo(eb?.nombre ?? '');
    });

    _filteredProductos = resultado;
  }

  /// Menor es más relevante: primero lo que empieza por lo tecleado.
  int _rangoRelevancia(_SearchEntry? entry, String consulta, String primero) {
    if (entry == null) return 3;
    if (entry.nombre.startsWith(consulta)) return 0;
    if (SearchText.algunaPalabraEmpiezaPor(entry.nombre, primero)) return 1;
    return 2;
  }

  /// Carga productos y categorías (network-first).
  /// [showLoading]: si es false, no bloquea la UI del POS con el indicador de carga.
  Future<void> loadProductos(String tiendaId, {bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final raw = await _syncService.loadProductos(tiendaId);
      _rawProductos = raw;
      _rebuildSearchIndex();
      _rebuildProductLists();
      _categorias = await _syncService.loadCategorias(tiendaId);
    } catch (e) {
      logDebug('❌ Error cargando productos: $e');
    }

    if (showLoading) {
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Refresca listas desde la base local (rápido tras registrar una venta).
  Future<void> refreshFromLocalCache(String tiendaId) async {
    try {
      final raw = await _syncService.loadProductosLocalOnly(tiendaId);
      _rawProductos = raw;
      _rebuildSearchIndex();
      _rebuildProductLists();
      _categorias = await _syncService.loadCategorias(tiendaId);
      notifyListeners();
    } catch (e) {
      logDebug('❌ Error refrescando productos desde caché: $e');
    }
  }

  /// Filtra productos por categoría, **sin descartar la búsqueda activa**.
  void filterByCategoria(String? categoriaId) {
    _selectedCategoriaId = categoriaId;
    _applyFilters();
    notifyListeners();
  }

  /// Resuelve producto por código (barras/QR). Si varios tienen el mismo código:
  /// prioriza sin proveedor, luego mayor existencia.
  ProductoModel? findProductByCodigo(String codigo) {
    final c = codigo.trim();
    if (c.isEmpty) return null;
    final candidatos = _allProductos
        .where((p) => p.codigos.any((cod) => cod.codigo.trim() == c))
        .toList();
    if (candidatos.isEmpty) return null;
    if (candidatos.length == 1) return candidatos.first;
    // Desempate: sin proveedor primero, luego mayor existencia
    candidatos.sort((a, b) {
      final aSinProv = (a.proveedor == null || a.proveedor!.isEmpty) ? 1 : 0;
      final bSinProv = (b.proveedor == null || b.proveedor!.isEmpty) ? 1 : 0;
      if (aSinProv != bSinProv) return bSinProv.compareTo(aSinProv);
      return b.existencia.compareTo(a.existencia);
    });
    return candidatos.first;
  }

  /// Busca en nombre, proveedor, descripción y códigos, ignorando tildes y
  /// admitiendo las palabras en cualquier orden ("coca 2" encuentra
  /// "Coca Cola 2L"). Respeta la categoría seleccionada.
  void searchProductos(String query) {
    _query = query;
    _applyFilters();
    notifyListeners();
  }

  /// Agrega un nuevo código a un producto tras una asociación exitosa.
  ///
  /// Escribe sobre `_rawProductos` (la fuente de verdad) y reconstruye las
  /// listas derivadas; si solo se tocara `_allProductos`, el próximo
  /// `_rebuildProductLists()` (tras una venta, cambio de conexión, etc.) lo
  /// regeneraría desde `_rawProductos` y perdería la asociación. Además persiste
  /// el código en la cache local para que sobreviva a un reinicio offline.
  Future<void> addCodigoToProducto(
    String productoTiendaId,
    CodigoProductoModel nuevoCodigo,
  ) async {
    final idx = _rawProductos.indexWhere((p) => p.id == productoTiendaId);
    if (idx == -1) return;

    final nuevosCodigos = [..._rawProductos[idx].codigos, nuevoCodigo];
    _rawProductos[idx] = _rawProductos[idx].copyWith(codigos: nuevosCodigos);
    // Cambia contenido buscable: hay que reindexar para poder buscar por el
    // código recién asociado.
    _rebuildSearchIndex();
    _rebuildProductLists();
    notifyListeners();

    try {
      await _syncService.productosLocal.updateCodigos(
        productoTiendaId,
        nuevosCodigos,
      );
    } catch (e) {
      logDebug('⚠️ Error persistiendo código asociado: $e');
    }
  }

  /// Actualiza existencia local después de venta
  void updateExistenciaLocal(String productoTiendaId, double cantidad) {
    final rawIdx = _rawProductos.indexWhere((p) => p.id == productoTiendaId);
    if (rawIdx != -1) {
      final old = _rawProductos[rawIdx];
      _rawProductos[rawIdx] = ProductoModel(
        id: old.id,
        productoId: old.productoId,
        nombre: old.nombre,
        descripcion: old.descripcion,
        precio: old.precio,
        costo: old.costo,
        existencia: old.existencia - cantidad,
        permiteDecimal: old.permiteDecimal,
        categoria: old.categoria,
        codigos: old.codigos,
        proveedor: old.proveedor,
        esFraccion: old.esFraccion,
        fraccionDe: old.fraccionDe,
        unidadesPorFraccion: old.unidadesPorFraccion,
      );
    }
    _rebuildProductLists();
    notifyListeners();
  }
}
