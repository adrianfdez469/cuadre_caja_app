import '../../data/models/producto_model.dart';
import '../../data/models/venta_model.dart';
import 'producto_pos_rules.dart';

/// Cálculo puro de las existencias resultantes tras una venta.
///
/// Devuelve **solo** las existencias de los productos que realmente cambian
/// (items del carrito + padres/hijos de las desagregaciones de productos
/// fracción), no de todo el catálogo. Es una función pura para poder testearla
/// de forma aislada y para que `crearVenta` escriba en un único batch/transacción.
class StockCalculator {
  /// Mapa `productoTiendaId -> nueva existencia` con solo los productos tocados.
  ///
  /// Replica exactamente la lógica que vivía inline en `SyncService.crearVenta`:
  /// 1) desagrega productos fracción cuya existencia local no alcanza la cantidad
  ///    vendida (resta al padre, suma unidades al hijo), y
  /// 2) resta lo vendido a cada item del carrito.
  static Map<String, double> existenciasTrasVenta(
    VentaLocalModel venta,
    List<ProductoModel> productos,
  ) {
    final byId = {for (final p in productos) p.id: p};
    final existencias = <String, double>{};

    // Existencia actual de un producto: el valor ya modificado si lo hay,
    // si no la existencia real del producto (nunca 0 por defecto).
    double currentOf(String id) => existencias[id] ?? byId[id]?.existencia ?? 0;

    // 1) Desagregaciones: fracción con existencia < cantidad a vender.
    for (final cartProd in venta.productos) {
      final p = byId[cartProd.productoTiendaId];
      if (p == null) continue;
      if (!ProductoPosRules.isFraccion(p)) continue;
      if (p.existencia >= cartProd.cantidad) continue;

      final need = cartProd.cantidad - p.existencia;
      final upf = (p.unidadesPorFraccion ?? 1).toDouble();
      final n = (need / upf).ceil().clamp(1, 0x7fffffff);
      final padreProductoId = p.fraccionDe?.id;
      if (padreProductoId == null) continue;

      final padres =
          productos.where((x) => x.productoId == padreProductoId).toList();
      final padre = padres.isEmpty ? null : padres.first;
      if (padre != null) {
        existencias[padre.id] = currentOf(padre.id) - n;
      }
      existencias[p.id] = currentOf(p.id) + (n * upf);
    }

    // 2) Restar lo vendido a cada item del carrito.
    for (final cartProd in venta.productos) {
      existencias[cartProd.productoTiendaId] =
          currentOf(cartProd.productoTiendaId) - cartProd.cantidad;
    }

    return existencias;
  }

  /// Existencias tras **devolver** al stock lo vendido en [venta] (anulación).
  ///
  /// Suma la cantidad vendida a cada producto de la venta y **no** intenta
  /// deshacer la desagregación de fracción que hizo [existenciasTrasVenta]: esa
  /// operación no es invertible (no se puede "re-empacar" un padre a partir de
  /// sus unidades sueltas), y la verdad final del padre la pone el servidor en
  /// el siguiente refresco de inventario. Es una asimetría deliberada.
  static Map<String, double> existenciasTrasRestauracion(
    VentaLocalModel venta,
    List<ProductoModel> productos,
  ) =>
      _ajusteDirecto(venta, productos, 1);

  /// Inverso exacto de [existenciasTrasRestauracion]: vuelve a descontar lo que
  /// se había devuelto. Se usa cuando el servidor **rechaza** una anulación que
  /// ya habíamos aplicado de forma optimista.
  static Map<String, double> existenciasTrasRollbackDeAnulacion(
    VentaLocalModel venta,
    List<ProductoModel> productos,
  ) =>
      _ajusteDirecto(venta, productos, -1);

  /// Suma [signo] × cantidad a cada producto de la venta, sin tocar fracciones.
  static Map<String, double> _ajusteDirecto(
    VentaLocalModel venta,
    List<ProductoModel> productos,
    double signo,
  ) {
    final byId = {for (final p in productos) p.id: p};
    final existencias = <String, double>{};

    double currentOf(String id) => existencias[id] ?? byId[id]?.existencia ?? 0;

    for (final prod in venta.productos) {
      existencias[prod.productoTiendaId] =
          currentOf(prod.productoTiendaId) + signo * prod.cantidad;
    }

    return existencias;
  }

  /// Re-aplica los decrementos de varias ventas **sobre** un snapshot de
  /// existencias (típicamente el del servidor), en orden, encadenando el estado.
  ///
  /// Sirve para reconciliar el inventario tras refrescar desde el servidor sin
  /// pisar el stock optimista de las operaciones que aún no se sincronizaron:
  ///
  /// ```
  /// existencia_local = snapshot_servidor − Σ(ventas pendientes)
  ///                                      + Σ(anulaciones pendientes)
  /// ```
  ///
  /// [anulaciones] son ventas **ya presentes en el snapshot del servidor** cuya
  /// anulación pedimos pero el servidor todavía no confirmó: su stock ya se
  /// devolvió localmente, así que hay que volver a sumarlo aquí o el refresco de
  /// inventario revertiría la devolución en silencio.
  ///
  /// Cada venta se aplica sobre el resultado de la anterior (la desagregación de
  /// fracción depende del stock corriente). Devuelve el mapa
  /// `productoTiendaId -> existencia final` **solo** de los productos tocados. No
  /// clampea: las existencias negativas son intencionales (se venden productos
  /// sin stock hasta que la venta sincronice, sin conexión o con el ajuste
  /// "Vender sin existencias" activo).
  static Map<String, double> replayVentas(
    List<ProductoModel> snapshot,
    List<VentaLocalModel> ventas, {
    List<VentaLocalModel> anulaciones = const [],
  }) {
    var productos = snapshot;
    final acumulado = <String, double>{};

    // Aplica [delta] al estado de trabajo para que la operación siguiente vea
    // el stock ya modificado por esta.
    void aplicar(Map<String, double> delta) {
      if (delta.isEmpty) return;
      acumulado.addAll(delta);
      productos = productos
          .map((p) => delta.containsKey(p.id)
              ? p.copyWith(existencia: delta[p.id])
              : p)
          .toList();
    }

    for (final venta in ventas) {
      aplicar(existenciasTrasVenta(venta, productos));
    }

    // Después de las ventas: una anulación devuelve stock que el snapshot del
    // servidor todavía da por vendido.
    for (final venta in anulaciones) {
      aplicar(existenciasTrasRestauracion(venta, productos));
    }

    return acumulado;
  }
}
