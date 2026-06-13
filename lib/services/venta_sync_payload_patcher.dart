import '../data/models/producto_model.dart';
import '../data/models/venta_model.dart';

/// Resultado de parchear una venta pendiente antes de sincronizar.
class VentaSyncPatchResult {
  final VentaLocalModel venta;
  final bool wasPatched;
  final List<String> fixesApplied;

  const VentaSyncPatchResult({
    required this.venta,
    required this.wasPatched,
    this.fixesApplied = const [],
  });
}

/// Parchea ventas creadas con la APK antigua para cumplir el contrato API actual.
///
/// Cubre el breaking change multimoneda del backend: rellena `monedaCobro`,
/// `pagosDetalle`, `vueltoDetalle` y `tasaSnapshot` a partir de `totalcash` /
/// `totaltransfer`, y corrige productos con `precio` o `name` faltantes.
class VentaSyncPayloadPatcher {
  VentaSyncPayloadPatcher._();

  /// Indica si la venta parece del formato pre-multimoneda o tiene datos incompletos.
  static bool needsPatch(VentaLocalModel venta) {
    if (venta.pagosDetalle.isEmpty) return true;
    if (venta.monedaCobro.isEmpty) return true;
    if (_productosNeedFix(venta.productos)) return true;
    if (_totalsNeedFix(venta)) return true;
    return false;
  }

  static bool _productosNeedFix(List<VentaProducto> productos) {
    for (final p in productos) {
      if (p.productoTiendaId.isEmpty) return true;
      if (p.precio <= 0) return true;
      if (p.cantidad <= 0) return true;
    }
    return false;
  }

  static bool _totalsNeedFix(VentaLocalModel venta) {
    if (venta.total <= 0) return false;
    return venta.totalcash <= 0 && venta.totaltransfer <= 0;
  }

  /// Aplica correcciones al payload y devuelve la venta lista para sincronizar.
  static VentaSyncPatchResult patch(
    VentaLocalModel venta, {
    List<ProductoModel> productos = const [],
  }) {
    final fixes = <String>[];
    var patched = venta;

    final fixedProductos = _fixProductos(venta.productos, productos, fixes);
    if (fixedProductos != venta.productos) {
      patched = patched.copyWith(productos: fixedProductos);
    }

    final beforeMultimoneda = patched;
    patched = VentaMultimonedaBuilder.ensureMultimoneda(patched);
    if (patched.pagosDetalle.isNotEmpty &&
        beforeMultimoneda.pagosDetalle.isEmpty) {
      fixes.add('multimoneda');
    }

    return VentaSyncPatchResult(
      venta: patched,
      wasPatched: fixes.isNotEmpty,
      fixesApplied: fixes,
    );
  }

  static List<VentaProducto> _fixProductos(
    List<VentaProducto> productos,
    List<ProductoModel> catalog,
    List<String> fixes,
  ) {
    if (productos.isEmpty) return productos;

    final byId = {for (final p in catalog) p.id: p};
    var changed = false;
    final result = <VentaProducto>[];

    for (final p in productos) {
      var precio = p.precio;
      var name = p.name;
      final cat = byId[p.productoTiendaId];

      if (precio <= 0 && cat != null) {
        precio = cat.precio;
        changed = true;
        fixes.add('precio:${p.productoTiendaId}');
      }
      if ((name == null || name.isEmpty) && cat != null) {
        name = cat.nombre;
        changed = true;
      }

      result.add(VentaProducto(
        productoTiendaId: p.productoTiendaId,
        cantidad: p.cantidad,
        name: name,
        precio: precio,
      ));
    }

    return changed ? result : productos;
  }

  /// Valida que el payload cumple los requisitos mínimos del API actual.
  static bool isPayloadReady(VentaLocalModel venta) {
    if (venta.syncId.isEmpty) return false;
    if (venta.createdAt <= 0) return false;
    if (venta.productos.isEmpty) return false;

    for (final p in venta.productos) {
      if (p.productoTiendaId.isEmpty) return false;
      if (p.cantidad <= 0) return false;
    }

    final api = venta.toApiJson();
    final pagos = api['pagosDetalle'];
    if (venta.total > 0) {
      if (pagos is! List || pagos.isEmpty) return false;
    }
    if (api['monedaCobro'] is! String ||
        (api['monedaCobro'] as String).isEmpty) {
      return false;
    }

    return true;
  }
}
