import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/utils/productos_vendidos_agregacion.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';

ProductoModel _producto(String id, {String? proveedor}) => ProductoModel(
  id: id,
  productoId: 'p-$id',
  nombre: id,
  precio: 100,
  costo: 50,
  existencia: 10,
  proveedor: proveedor,
);

VentaUnificadaModel _venta({
  required String id,
  required List<VentaProducto> productos,
  double totalcash = 0,
  double totaltransfer = 0,
  double discountTotal = 0,
  String? transferDestinationId,
  String? usuarioId,
  int createdAtMs = 0,
  SyncState syncState = SyncState.synced,
}) {
  final total = productos.fold<double>(0, (s, p) => s + p.precio * p.cantidad);
  return VentaUnificadaModel(
    identifier: id,
    tiendaId: 't1',
    periodoId: 'per1',
    total: total,
    totalcash: totalcash,
    totaltransfer: totaltransfer,
    discountTotal: discountTotal,
    createdAtMs: createdAtMs,
    synced: syncState == SyncState.synced,
    syncState: syncState,
    productos: productos,
    transferDestinationId: transferDestinationId,
    usuarioId: usuarioId,
  );
}

VentaProducto _linea(String productoId, double cantidad, double precio) =>
    VentaProducto(
      productoTiendaId: productoId,
      cantidad: cantidad,
      precio: precio,
      name: productoId,
    );

void main() {
  final proveedores = ProductosVendidosAgregacion.proveedorPorProducto([
    _producto('cola'),
    _producto('pan', proveedor: 'Panadería Sur'),
    _producto('agua', proveedor: 'Distribuidora Norte'),
  ]);

  const todos = {kFiltroTodos};

  group('agrupados', () {
    test('suma cantidades y totales del mismo producto', () {
      final agrupados = ProductosVendidosAgregacion.agrupados(
        [
          _venta(id: 'v1', productos: [_linea('cola', 2, 100)]),
          _venta(id: 'v2', productos: [_linea('cola', 3, 100)]),
        ],
        proveedores,
        todos,
      );

      expect(agrupados, hasLength(1));
      expect(agrupados.single.cantidad, 5);
      expect(agrupados.single.total, 500);
      expect(agrupados.single.preciosDistintos, isFalse);
    });

    test(
      'con dos precios distintos el precio unitario sigue cuadrando con el total',
      () {
        // Este era el fallo: se guardaba el precio de la última venta
        // procesada, así que `precio × cantidad` no daba el total.
        final agrupados = ProductosVendidosAgregacion.agrupados(
          [
            _venta(id: 'v1', productos: [_linea('cola', 2, 100)]),
            _venta(id: 'v2', productos: [_linea('cola', 2, 200)]),
          ],
          proveedores,
          todos,
        );

        final p = agrupados.single;
        expect(p.cantidad, 4);
        expect(p.total, 600);
        expect(p.precioUnitario, 150);
        expect(p.precioUnitario * p.cantidad, p.total);
        expect(
          p.preciosDistintos,
          isTrue,
          reason: 'la columna debe rotularse "P. medio"',
        );
      },
    );

    test('ordena por importe y desempata por nombre', () {
      final agrupados = ProductosVendidosAgregacion.agrupados(
        [
          _venta(
            id: 'v1',
            productos: [
              _linea('pan', 1, 100),
              _linea('agua', 1, 100),
              _linea('cola', 10, 100),
            ],
          ),
        ],
        proveedores,
        todos,
      );

      expect(agrupados.map((p) => p.nombre), ['cola', 'agua', 'pan']);
    });

    test('ordena por unidades cuando se pide', () {
      final agrupados = ProductosVendidosAgregacion.agrupados(
        [
          _venta(
            id: 'v1',
            productos: [_linea('cola', 1, 1000), _linea('pan', 5, 10)],
          ),
        ],
        proveedores,
        todos,
        orden: OrdenProductosVendidos.unidades,
      );

      expect(agrupados.first.nombre, 'pan');
    });
  });

  group('filtro de proveedor', () {
    test('"Productos propios" deja fuera lo que tiene proveedor', () {
      final agrupados = ProductosVendidosAgregacion.agrupados(
        [
          _venta(
            id: 'v1',
            productos: [_linea('cola', 1, 100), _linea('pan', 1, 100)],
          ),
        ],
        proveedores,
        {kFiltroPropios},
      );

      expect(agrupados.map((p) => p.nombre), ['cola']);
    });

    test('un proveedor concreto deja fuera lo propio y a los demás', () {
      final agrupados = ProductosVendidosAgregacion.agrupados(
        [
          _venta(
            id: 'v1',
            productos: [
              _linea('cola', 1, 100),
              _linea('pan', 1, 100),
              _linea('agua', 1, 100),
            ],
          ),
        ],
        proveedores,
        {'Panadería Sur'},
      );

      expect(agrupados.map((p) => p.nombre), ['pan']);
    });
  });

  group('filtro de vendedor', () {
    test('una venta local sin usuarioId cuenta como del usuario actual', () {
      final ventas = [
        _venta(id: 'local', productos: [_linea('cola', 1, 100)]),
        _venta(
          id: 'otro',
          productos: [_linea('cola', 1, 100)],
          usuarioId: 'u2',
        ),
      ];

      final mias = ProductosVendidosAgregacion.ventasFiltradas(ventas, {
        'u1',
      }, 'u1');

      expect(mias.map((v) => v.identifier), ['local']);
    });
  });

  group('resumen', () {
    test('cuadra el desglose de pago cuando no hay filtro de proveedor', () {
      final r = ProductosVendidosAgregacion.resumen(
        [
          _venta(
            id: 'v1',
            productos: [_linea('cola', 2, 100), _linea('pan', 1, 50)],
            totalcash: 150,
            totaltransfer: 100,
          ),
        ],
        proveedores,
        todos,
      );

      expect(r.totalVendido, 250);
      expect(r.unidades, 3);
      expect(r.productosDistintos, 2);
      expect(r.desglosePagoDisponible, isTrue);
      expect(r.efectivo + r.transferencia, r.totalVendido);
    });

    test('los descuentos explican la diferencia entre vendido y cobrado', () {
      final r = ProductosVendidosAgregacion.resumen(
        [
          _venta(
            id: 'v1',
            productos: [_linea('cola', 1, 100)],
            totalcash: 80,
            discountTotal: 20,
          ),
        ],
        proveedores,
        todos,
      );

      expect(r.totalVendido, 100);
      expect(r.efectivo + r.transferencia + r.descuentos, r.totalVendido);
    });

    test('con filtro de proveedor no se reparte el pago', () {
      // Una venta puede mezclar proveedores y su pago no se puede atribuir a
      // uno: mostrar un número ahí sería inventarlo.
      final r = ProductosVendidosAgregacion.resumen(
        [
          _venta(
            id: 'v1',
            productos: [_linea('cola', 1, 100), _linea('pan', 1, 100)],
            totalcash: 200,
          ),
        ],
        proveedores,
        {kFiltroPropios},
      );

      expect(r.totalVendido, 100, reason: 'sólo el ítem propio');
      expect(r.desglosePagoDisponible, isFalse);
      expect(r.efectivo, 0);
    });

    test('agrupa las transferencias por destino', () {
      final r = ProductosVendidosAgregacion.resumen(
        [
          _venta(
            id: 'v1',
            productos: [_linea('cola', 1, 100)],
            totaltransfer: 100,
            transferDestinationId: 'd1',
          ),
          _venta(
            id: 'v2',
            productos: [_linea('cola', 1, 50)],
            totaltransfer: 50,
            transferDestinationId: 'd1',
          ),
          _venta(
            id: 'v3',
            productos: [_linea('cola', 1, 30)],
            totaltransfer: 30,
          ),
        ],
        proveedores,
        todos,
      );

      expect(r.transferenciaPorDestino['d1'], 150);
      expect(r.transferenciaPorDestino[kSinDestino], 30);
    });

    test('avisa de las ventas sin subir y con error incluidas en el total', () {
      final r = ProductosVendidosAgregacion.resumen(
        [
          _venta(id: 'v1', productos: [_linea('cola', 1, 100)]),
          _venta(
            id: 'v2',
            productos: [_linea('cola', 1, 100)],
            syncState: SyncState.pending,
          ),
          _venta(
            id: 'v3',
            productos: [_linea('cola', 1, 100)],
            syncState: SyncState.error,
          ),
          _venta(
            id: 'v4',
            productos: [_linea('cola', 1, 100)],
            syncState: SyncState.cancelError,
          ),
        ],
        proveedores,
        todos,
      );

      expect(r.ventasSinSubir, 1);
      expect(r.ventasConError, 2);
    });
  });
}
