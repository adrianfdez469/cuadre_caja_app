import '../../data/models/producto_model.dart';

/// Reglas de negocio POS para productos (según ESPECIFICACIONES_PRODUCTOS_POS.md).
/// Disponibilidad, máximos, filtrado y desagregación.
class ProductoPosRules {
  /// Indica si el producto es fracción (tiene padre y unidadesPorFraccion válido).
  static bool isFraccion(ProductoModel p) {
    return (p.fraccionDe != null &&
        p.unidadesPorFraccion != null &&
        p.unidadesPorFraccion! > 0);
  }

  /// Existencia real del producto (>= 0).
  static double existenciaReal(ProductoModel p) {
    return (p.existencia > 0) ? p.existencia : 0;
  }

  /// Producto padre en la lista (por fraccionDe.id = productoId del padre).
  static ProductoModel? findPadre(
    ProductoModel hijo,
    List<ProductoModel> productos,
  ) {
    final padreId = hijo.fraccionDe?.id;
    if (padreId == null) return null;
    try {
      return productos.firstWhere((p) => p.productoId == padreId);
    } catch (_) {
      return null;
    }
  }

  /// Disponibilidad total para producto fracción: existencia + (existencia padre * unidadesPorFraccion).
  static double disponibilidadTotalFraccion(
    ProductoModel p,
    List<ProductoModel> productos,
  ) {
    final exist = existenciaReal(p);
    final padre = findPadre(p, productos);
    final existPadre = padre != null ? existenciaReal(padre) : 0.0;
    final upf = (p.unidadesPorFraccion ?? 0).toDouble();
    return exist + (existPadre * upf);
  }

  /// Máximo por transacción para fracción: min(disponibilidadTotal, unidadesPorFraccion - 1).
  static double maxPorTransaccionFraccion(
    ProductoModel p,
    List<ProductoModel> productos,
  ) {
    final total = disponibilidadTotalFraccion(p, productos);
    final maxF = ((p.unidadesPorFraccion ?? 1) - 1).toDouble();
    if (maxF <= 0) return 0;
    return total < maxF ? total : maxF;
  }

  /// Máximo permitido para mostrar/agregar (considerando ya en carrito).
  /// Normal: existencia. Fracción: min(disponibilidadTotal, unidadesPorFraccion - 1).
  static double getMaxQuantity(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
  }) {
    double max;
    if (isFraccion(p)) {
      max = maxPorTransaccionFraccion(p, productos);
    } else {
      max = existenciaReal(p);
    }
    final disponible = max - cantidadEnCarrito;
    return disponible > 0 ? disponible : 0;
  }

  /// Disponible para mostrar en listado (mismo que getMaxQuantity con cantidadEnCarrito).
  static double disponibleParaMostrar(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
  }) {
    return getMaxQuantity(
      p,
      productos,
      cantidadEnCarrito: cantidadEnCarrito,
    );
  }

  /// ¿Se debe mostrar el producto en POS? precio > 0 y (existencia > 0 o fracción con padre con existencia).
  static bool debeMostrarEnPos(
    ProductoModel p,
    List<ProductoModel> productos,
  ) {
    if (p.precio <= 0) return false;
    if (p.existencia > 0) return true;
    if (isFraccion(p)) {
      final padre = findPadre(p, productos);
      if (padre != null && padre.existencia > 0) return true;
    }
    return false;
  }

  /// Filtra y ordena lista para POS: precio > 0, existencia (con excepción fracción), orden por nombre.
  static List<ProductoModel> filtrarYOrdenarParaPos(
    List<ProductoModel> productos,
  ) {
    final list = productos.where((p) => debeMostrarEnPos(p, productos)).toList();
    list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return list;
  }

  /// Nombre para mostrar: "nombre" o "nombre - proveedor" si tiene proveedor.
  static String nombreParaMostrar(ProductoModel p) {
    if (p.proveedor != null && p.proveedor!.trim().isNotEmpty) {
      return '${p.nombre} - ${p.proveedor!.trim()}';
    }
    return p.nombre;
  }
}
