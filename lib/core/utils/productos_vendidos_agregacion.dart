import '../../data/models/producto_model.dart';
import '../../data/models/venta_model.dart';

/// Clave del chip "Todos" en los filtros de vendedor y proveedor.
const kFiltroTodos = '_todos_';

/// Clave del chip "Productos propios": los que no tienen proveedor.
const kFiltroPropios = '_propios_';

/// Clave de las transferencias sin destino declarado.
const kSinDestino = '_sin_destino_';

/// Cómo se ordena la lista de productos vendidos.
enum OrdenProductosVendidos { importe, unidades, alfabetico, reciente }

extension OrdenProductosVendidosLabel on OrdenProductosVendidos {
  String get label => switch (this) {
    OrdenProductosVendidos.importe => 'Más vendido',
    OrdenProductosVendidos.unidades => 'Más unidades',
    OrdenProductosVendidos.alfabetico => 'A – Z',
    OrdenProductosVendidos.reciente => 'Más reciente',
  };
}

/// Una línea vendida, una por producto y venta (vista histórica).
class ProductoVendidoItem {
  final String productoTiendaId;
  final String nombre;
  final String? proveedor;
  final double cantidad;
  final double precio;
  final double total;
  final int ventaCreatedAtMs;
  final SyncState syncState;

  const ProductoVendidoItem({
    required this.productoTiendaId,
    required this.nombre,
    required this.proveedor,
    required this.cantidad,
    required this.precio,
    required this.total,
    required this.ventaCreatedAtMs,
    required this.syncState,
  });
}

/// Un producto con todas sus ventas del período sumadas.
class ProductoVendidoAgrupado {
  final String productoTiendaId;
  final String nombre;
  final String? proveedor;
  final double cantidad;
  final double total;
  final int ultimaVentaMs;

  /// El producto se vendió a más de un precio en el período (cambio de precio,
  /// descuento puntual). Cuando pasa, la columna deja de poder rotularse
  /// "Precio" a secas.
  final bool preciosDistintos;

  const ProductoVendidoAgrupado({
    required this.productoTiendaId,
    required this.nombre,
    required this.proveedor,
    required this.cantidad,
    required this.total,
    required this.ultimaVentaMs,
    required this.preciosDistintos,
  });

  /// Precio unitario **derivado del total**, no el de la última venta que se
  /// procesó. Antes se guardaba el último y `precio × cantidad` no daba el
  /// total en cuanto el producto se había vendido a dos precios.
  double get precioUnitario => cantidad == 0 ? 0 : total / cantidad;
}

/// Los totales de la cabecera, con lo que hace falta para saber si son fiables.
class ResumenVendido {
  final double totalVendido;
  final double unidades;
  final int productosDistintos;

  /// El reparto por forma de pago se agrega **por venta**, mientras que
  /// [totalVendido] se agrega por ítem. Con un filtro de proveedor activo las
  /// dos cifras dejan de ser comparables —una venta puede mezclar proveedores y
  /// su pago no se puede repartir entre ellos— así que en ese caso no se
  /// muestra en vez de enseñar un número que no cuadra.
  final bool desglosePagoDisponible;
  final double efectivo;
  final double transferencia;
  final double descuentos;
  final Map<String, double> transferenciaPorDestino;

  /// Ventas incluidas en estos totales que todavía no están en el servidor.
  final int ventasSinSubir;
  final int ventasConError;

  const ResumenVendido({
    required this.totalVendido,
    required this.unidades,
    required this.productosDistintos,
    required this.desglosePagoDisponible,
    required this.efectivo,
    required this.transferencia,
    required this.descuentos,
    required this.transferenciaPorDestino,
    required this.ventasSinSubir,
    required this.ventasConError,
  });
}

/// Agregaciones de "Productos vendidos".
///
/// Están fuera del `State` a propósito: se recalculaban enteras en cada
/// `build`, y sin salir del widget no había forma de comprobar con un test que
/// el precio unitario cuadrara con el total.
class ProductosVendidosAgregacion {
  const ProductosVendidosAgregacion._();

  /// Mapa `productoTiendaId → proveedor`. Un proveedor vacío es "propio".
  static Map<String, String?> proveedorPorProducto(
    List<ProductoModel> productos,
  ) {
    final map = <String, String?>{};
    for (final p in productos) {
      final prov = p.proveedor?.trim();
      map[p.id] = (prov == null || prov.isEmpty) ? null : prov;
    }
    return map;
  }

  static bool pasaFiltroProveedor(String? proveedor, Set<String> seleccion) {
    if (seleccion.isEmpty || seleccion.contains(kFiltroTodos)) return true;
    final esPropio = proveedor == null || proveedor.isEmpty;
    if (esPropio) return seleccion.contains(kFiltroPropios);
    return seleccion.contains(proveedor);
  }

  static bool pasaFiltroVendedor(
    VentaUnificadaModel venta,
    Set<String> seleccion,
    String? usuarioActualId,
  ) {
    if (seleccion.isEmpty || seleccion.contains(kFiltroTodos)) return true;
    // Las ventas locales aún no tienen `usuarioId`: son de quien está usando el
    // dispositivo.
    final id = venta.usuarioId ?? usuarioActualId;
    if (id == null) return false;
    return seleccion.contains(id);
  }

  static List<VentaUnificadaModel> ventasFiltradas(
    List<VentaUnificadaModel> ventas,
    Set<String> vendedores,
    String? usuarioActualId,
  ) {
    return ventas
        .where((v) => pasaFiltroVendedor(v, vendedores, usuarioActualId))
        .toList();
  }

  static List<ProductoVendidoItem> historicos(
    List<VentaUnificadaModel> ventas,
    Map<String, String?> proveedorPorProducto,
    Set<String> proveedores,
  ) {
    final list = <ProductoVendidoItem>[];
    for (final v in ventas) {
      for (final p in v.productos) {
        final prov = proveedorPorProducto[p.productoTiendaId];
        if (!pasaFiltroProveedor(prov, proveedores)) continue;
        list.add(
          ProductoVendidoItem(
            productoTiendaId: p.productoTiendaId,
            nombre: p.name ?? 'Producto',
            proveedor: prov,
            cantidad: p.cantidad,
            precio: p.precio,
            total: p.precio * p.cantidad,
            ventaCreatedAtMs: v.createdAtMs,
            syncState: v.syncState,
          ),
        );
      }
    }
    list.sort((a, b) => b.ventaCreatedAtMs.compareTo(a.ventaCreatedAtMs));
    return list;
  }

  static List<ProductoVendidoAgrupado> agrupados(
    List<VentaUnificadaModel> ventas,
    Map<String, String?> proveedorPorProducto,
    Set<String> proveedores, {
    OrdenProductosVendidos orden = OrdenProductosVendidos.importe,
  }) {
    final nombres = <String, String>{};
    final provs = <String, String?>{};
    final cantidades = <String, double>{};
    final totales = <String, double>{};
    final ultimas = <String, int>{};
    final precios = <String, Set<double>>{};

    for (final v in ventas) {
      for (final p in v.productos) {
        final prov = proveedorPorProducto[p.productoTiendaId];
        if (!pasaFiltroProveedor(prov, proveedores)) continue;
        final id = p.productoTiendaId;
        nombres.putIfAbsent(id, () => p.name ?? 'Producto');
        provs.putIfAbsent(id, () => prov);
        cantidades[id] = (cantidades[id] ?? 0) + p.cantidad;
        totales[id] = (totales[id] ?? 0) + p.precio * p.cantidad;
        ultimas[id] = (ultimas[id] ?? 0) > v.createdAtMs
            ? ultimas[id]!
            : v.createdAtMs;
        (precios[id] ??= <double>{}).add(p.precio);
      }
    }

    final list = [
      for (final id in nombres.keys)
        ProductoVendidoAgrupado(
          productoTiendaId: id,
          nombre: nombres[id]!,
          proveedor: provs[id],
          cantidad: cantidades[id] ?? 0,
          total: totales[id] ?? 0,
          ultimaVentaMs: ultimas[id] ?? 0,
          preciosDistintos: (precios[id]?.length ?? 0) > 1,
        ),
    ];

    // `List.sort` de Dart no es estable: el desempate por nombre es explícito
    // para que dos productos con el mismo importe no bailen entre refrescos.
    int porNombre(ProductoVendidoAgrupado a, ProductoVendidoAgrupado b) =>
        a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());

    list.sort(
      (a, b) => switch (orden) {
        OrdenProductosVendidos.importe =>
          b.total.compareTo(a.total) != 0
              ? b.total.compareTo(a.total)
              : porNombre(a, b),
        OrdenProductosVendidos.unidades =>
          b.cantidad.compareTo(a.cantidad) != 0
              ? b.cantidad.compareTo(a.cantidad)
              : porNombre(a, b),
        OrdenProductosVendidos.alfabetico => porNombre(a, b),
        OrdenProductosVendidos.reciente =>
          b.ultimaVentaMs.compareTo(a.ultimaVentaMs) != 0
              ? b.ultimaVentaMs.compareTo(a.ultimaVentaMs)
              : porNombre(a, b),
      },
    );
    return list;
  }

  static ResumenVendido resumen(
    List<VentaUnificadaModel> ventas,
    Map<String, String?> proveedorPorProducto,
    Set<String> proveedores,
  ) {
    final restrictivo =
        !(proveedores.isEmpty || proveedores.contains(kFiltroTodos));

    var totalVendido = 0.0;
    var unidades = 0.0;
    var efectivo = 0.0;
    var transferencia = 0.0;
    var descuentos = 0.0;
    var sinSubir = 0;
    var conError = 0;
    final distintos = <String>{};
    final porDestino = <String, double>{};

    for (final v in ventas) {
      var aporta = false;
      for (final p in v.productos) {
        final prov = proveedorPorProducto[p.productoTiendaId];
        if (!pasaFiltroProveedor(prov, proveedores)) continue;
        aporta = true;
        totalVendido += p.precio * p.cantidad;
        unidades += p.cantidad;
        distintos.add(p.productoTiendaId);
      }
      if (!aporta) continue;

      final esError =
          v.syncState == SyncState.error ||
          v.syncState == SyncState.cancelError;
      if (esError) {
        conError++;
      } else if (!v.synced) {
        sinSubir++;
      }

      if (restrictivo) continue;
      efectivo += v.totalcash;
      transferencia += v.totaltransfer;
      descuentos += v.discountTotal;
      if (v.totaltransfer > 0) {
        final id = v.transferDestinationId ?? kSinDestino;
        porDestino[id] = (porDestino[id] ?? 0) + v.totaltransfer;
      }
    }

    return ResumenVendido(
      totalVendido: totalVendido,
      unidades: unidades,
      productosDistintos: distintos.length,
      desglosePagoDisponible: !restrictivo,
      efectivo: efectivo,
      transferencia: transferencia,
      descuentos: descuentos,
      transferenciaPorDestino: porDestino,
      ventasSinSubir: sinSubir,
      ventasConError: conError,
    );
  }
}
