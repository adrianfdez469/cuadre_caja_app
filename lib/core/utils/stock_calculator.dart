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

  /// Re-aplica los decrementos de varias ventas **sobre** un snapshot de
  /// existencias (típicamente el del servidor), en orden, encadenando el estado.
  ///
  /// Sirve para reconciliar el inventario tras refrescar desde el servidor sin
  /// pisar el stock optimista de las ventas que aún no se sincronizaron:
  /// `existencia_local = snapshot_servidor − Σ(decrementos no sincronizados)`.
  ///
  /// Cada venta se aplica sobre el resultado de la anterior (la desagregación de
  /// fracción depende del stock corriente). Devuelve el mapa
  /// `productoTiendaId -> existencia final` **solo** de los productos tocados por
  /// alguna venta. No clampea: permitir existencias negativas offline es
  /// intencional (se venden productos sin stock hasta que la venta sincronice).
  static Map<String, double> replayVentas(
    List<ProductoModel> snapshot,
    List<VentaLocalModel> ventas,
  ) {
    var productos = snapshot;
    final acumulado = <String, double>{};

    for (final venta in ventas) {
      final delta = existenciasTrasVenta(venta, productos);
      if (delta.isEmpty) continue;
      acumulado.addAll(delta);
      // Aplicar al estado de trabajo para que la siguiente venta vea el stock
      // ya decrementado por esta.
      productos = productos
          .map((p) => delta.containsKey(p.id)
              ? p.copyWith(existencia: delta[p.id])
              : p)
          .toList();
    }

    return acumulado;
  }
}
