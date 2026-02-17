import 'package:flutter/foundation.dart';
import '../data/models/producto_model.dart';
import '../data/models/categoria_model.dart';
import '../services/sync_service.dart';

class ProductosProvider extends ChangeNotifier {
  final SyncService _syncService;

  List<ProductoModel> _allProductos = [];
  List<ProductoModel> _filteredProductos = [];
  List<CategoriaModel> _categorias = [];
  bool _isLoading = false;
  String? _selectedCategoriaId;

  ProductosProvider(this._syncService);

  List<ProductoModel> get productos => _filteredProductos;
  List<ProductoModel> get allProductos => _allProductos;
  List<CategoriaModel> get categorias => _categorias;
  bool get isLoading => _isLoading;
  String? get selectedCategoriaId => _selectedCategoriaId;

  /// Carga productos y categorías (network-first)
  Future<void> loadProductos(String tiendaId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _allProductos = await _syncService.loadProductos(tiendaId);
      _categorias = await _syncService.loadCategorias(tiendaId);

      // Si ya hay una categoría seleccionada, filtrar
      if (_selectedCategoriaId != null) {
        _filteredProductos = _allProductos
            .where((p) => p.categoriaId == _selectedCategoriaId)
            .toList();
      } else {
        _filteredProductos = List.from(_allProductos);
      }
    } catch (e) {
      print('❌ Error cargando productos: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Filtra productos por categoría
  void filterByCategoria(String? categoriaId) {
    _selectedCategoriaId = categoriaId;

    if (categoriaId == null) {
      _filteredProductos = List.from(_allProductos);
    } else {
      _filteredProductos = _allProductos
          .where((p) => p.categoriaId == categoriaId)
          .toList();
    }
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

  /// Búsqueda global por nombre (case-insensitive), para POS. No modifica categoría.
  List<ProductoModel> searchByName(String query, {int limit = 10}) {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final list = _allProductos
        .where((p) => p.nombre.toLowerCase().contains(q))
        .take(limit)
        .toList();
    return list;
  }

  /// Busca productos por nombre
  void searchProductos(String query) {
    if (query.isEmpty) {
      filterByCategoria(_selectedCategoriaId);
      return;
    }

    final lowQuery = query.toLowerCase();
    _filteredProductos = _allProductos.where((p) {
      final matchName = p.nombre.toLowerCase().contains(lowQuery);
      final matchDesc = p.descripcion?.toLowerCase().contains(lowQuery) ?? false;
      final matchCode = p.codigos.any((c) => c.codigo.contains(query));
      final matchCategoria = _selectedCategoriaId == null ||
          p.categoriaId == _selectedCategoriaId;
      return (matchName || matchDesc || matchCode) && matchCategoria;
    }).toList();

    notifyListeners();
  }

  /// Actualiza existencia local después de venta
  void updateExistenciaLocal(String productoTiendaId, double cantidad) {
    final idx = _allProductos.indexWhere((p) => p.id == productoTiendaId);
    if (idx != -1) {
      final old = _allProductos[idx];
      _allProductos[idx] = ProductoModel(
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
    // Re-aplicar filtro
    filterByCategoria(_selectedCategoriaId);
  }
}
