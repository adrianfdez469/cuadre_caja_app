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
    List<ProductoModel> productos, {
    bool offlineMode = false,
  }) {
    final maxF = ((p.unidadesPorFraccion ?? 1) - 1).toDouble();
    if (maxF <= 0) return 0;
    if (offlineMode) return maxF;
    final total = disponibilidadTotalFraccion(p, productos);
    return total < maxF ? total : maxF;
  }

  /// Indica si hay stock local suficiente según la caché del dispositivo.
  static bool tieneStockLocal(
    ProductoModel p,
    List<ProductoModel> productos,
  ) {
    if (isFraccion(p)) {
      return disponibilidadTotalFraccion(p, productos) > 0;
    }
    return p.existencia > 0;
  }

  /// Existencia local disponible descontando lo ya en carrito(s).
  static double existenciaLocalEfectiva(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
  }) {
    if (isFraccion(p)) {
      final total = disponibilidadTotalFraccion(p, productos) - cantidadEnCarrito;
      return total > 0 ? total : 0;
    }
    final restante = existenciaReal(p) - cantidadEnCarrito;
    return restante > 0 ? restante : 0;
  }

  /// Stock local visible para UI offline (caché menos carrito).
  static bool tieneStockLocalEfectivo(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
  }) {
    return existenciaLocalEfectiva(
          p,
          productos,
          cantidadEnCarrito: cantidadEnCarrito,
        ) >
        0;
  }

  /// Máximo permitido para mostrar/agregar (considerando ya en carrito).
  /// Online: normal = existencia; fracción = min(disponibilidadTotal, upf - 1).
  /// Offline: normal = sin límite; fracción = solo upf - 1.
  static double getMaxQuantity(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
    bool offlineMode = false,
  }) {
    double max;
    if (isFraccion(p)) {
      max = maxPorTransaccionFraccion(p, productos, offlineMode: offlineMode);
    } else if (offlineMode) {
      return double.infinity;
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
    bool offlineMode = false,
  }) {
    return getMaxQuantity(
      p,
      productos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );
  }

  /// ¿Se puede agregar al carrito?
  static bool puedeAgregar(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
    bool offlineMode = false,
  }) {
    if (offlineMode && !isFraccion(p)) return true;
    return getMaxQuantity(
          p,
          productos,
          cantidadEnCarrito: cantidadEnCarrito,
          offlineMode: offlineMode,
        ) >
        0;
  }

  /// ¿Se debe mostrar el producto en POS?
  /// Online: precio > 0 y stock local (con excepción fracción).
  /// Offline: precio > 0 siempre.
  static bool debeMostrarEnPos(
    ProductoModel p,
    List<ProductoModel> productos, {
    bool offlineMode = false,
  }) {
    if (p.precio <= 0) return false;
    if (offlineMode) return true;
    if (p.existencia > 0) return true;
    if (isFraccion(p)) {
      final padre = findPadre(p, productos);
      if (padre != null && padre.existencia > 0) return true;
    }
    return false;
  }

  /// Filtra y ordena lista para POS.
  static List<ProductoModel> filtrarYOrdenarParaPos(
    List<ProductoModel> productos, {
    bool offlineMode = false,
  }) {
    final list = productos
        .where((p) => debeMostrarEnPos(p, productos, offlineMode: offlineMode))
        .toList();
    list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return list;
  }

  /// Formatea cantidad según si el producto permite decimales.
  static String formatearCantidad(ProductoModel p, double cantidad) {
    return cantidad.toStringAsFixed(p.permiteDecimal ? 1 : 0);
  }

  /// Texto de stock para cards/listados del POS.
  /// Offline con existencia local > 0: muestra la cantidad restante local.
  /// Offline sin stock local: vacío (el badge "Sin stock local" cubre ese caso).
  static String textoStockEnCard(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
    bool offlineMode = false,
  }) {
    final esFraccion = isFraccion(p);
    final exist = existenciaReal(p);

    if (offlineMode) {
      final efectiva = existenciaLocalEfectiva(
        p,
        productos,
        cantidadEnCarrito: cantidadEnCarrito,
      );
      if (efectiva <= 0) return '';
      if (esFraccion) {
        final maxDisp = getMaxQuantity(
          p,
          productos,
          cantidadEnCarrito: cantidadEnCarrito,
          offlineMode: true,
        );
        return 'Stock: ${formatearCantidad(p, exist)} | Máx: ${formatearCantidad(p, maxDisp)}';
      }
      return 'Cant: ${formatearCantidad(p, efectiva)}';
    }

    final disponible = disponibleParaMostrar(
      p,
      productos,
      cantidadEnCarrito: cantidadEnCarrito,
    );
    if (esFraccion) {
      return 'Stock: ${formatearCantidad(p, exist)} | Máx: ${formatearCantidad(p, disponible)}';
    }
    return 'Cant: ${formatearCantidad(p, disponible)}';
  }

  /// Texto de stock para diálogos de cantidad.
  static String textoStockEnDialogo(
    ProductoModel p,
    List<ProductoModel> productos, {
    double cantidadEnCarrito = 0,
    bool offlineMode = false,
  }) {
    final esFraccion = isFraccion(p);
    final exist = existenciaReal(p);

    if (offlineMode) {
      final efectiva = existenciaLocalEfectiva(
        p,
        productos,
        cantidadEnCarrito: cantidadEnCarrito,
      );
      if (efectiva <= 0) {
        if (esFraccion) {
          final maxDisp = getMaxQuantity(
            p,
            productos,
            cantidadEnCarrito: cantidadEnCarrito,
            offlineMode: true,
          );
          return 'Stock local agotado en carrito | Máx. por venta: ${formatearCantidad(p, maxDisp)} (offline)';
        }
        return 'Sin stock local — venta permitida offline';
      }
      if (esFraccion) {
        final maxDisp = getMaxQuantity(
          p,
          productos,
          cantidadEnCarrito: cantidadEnCarrito,
          offlineMode: true,
        );
        return 'Stock: ${formatearCantidad(p, exist)} | Máx. por venta: ${formatearCantidad(p, maxDisp)}';
      }
      return 'Disponibles (local): ${formatearCantidad(p, efectiva)}';
    }

    final maxDisp = getMaxQuantity(
      p,
      productos,
      cantidadEnCarrito: cantidadEnCarrito,
    );
    if (esFraccion) {
      return 'Stock: ${formatearCantidad(p, exist)} | Máx. por venta: ${formatearCantidad(p, maxDisp)}';
    }
    return 'Disponibles: ${formatearCantidad(p, maxDisp)}';
  }

  /// Nombre para mostrar: "nombre" o "nombre - proveedor" si tiene proveedor.
  static String nombreParaMostrar(ProductoModel p) {
    if (p.proveedor != null && p.proveedor!.trim().isNotEmpty) {
      return '${p.nombre} - ${p.proveedor!.trim()}';
    }
    return p.nombre;
  }
}
