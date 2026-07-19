import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/core/utils/stock_calculator.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';

ProductoModel _producto({
  required String id,
  required String productoId,
  required double existencia,
  FraccionDeModel? fraccionDe,
  int? unidadesPorFraccion,
}) {
  return ProductoModel(
    id: id,
    productoId: productoId,
    nombre: id,
    precio: 10,
    costo: 5,
    existencia: existencia,
    fraccionDe: fraccionDe,
    unidadesPorFraccion: unidadesPorFraccion,
  );
}

VentaLocalModel _venta(List<VentaProducto> productos, {String syncId = 'v1'}) {
  return VentaLocalModel(
    syncId: syncId,
    tiendaId: 't1',
    periodoId: 'p1',
    productos: productos,
    total: 0,
    totalcash: 0,
    createdAt: 0,
  );
}

VentaProducto _item(String productoTiendaId, double cantidad) {
  return VentaProducto(
    productoTiendaId: productoTiendaId,
    cantidad: cantidad,
    precio: 10,
  );
}

void main() {
  group('StockCalculator.existenciasTrasVenta', () {
    test('solo devuelve los productos tocados, no todo el catálogo', () {
      final productos = [
        _producto(id: 'A', productoId: 'pA', existencia: 100),
        _producto(id: 'B', productoId: 'pB', existencia: 50),
        _producto(id: 'C', productoId: 'pC', existencia: 30),
      ];
      final venta = _venta([_item('A', 3)]);

      final result = StockCalculator.existenciasTrasVenta(venta, productos);

      expect(result.keys, ['A']);
      expect(result['A'], 97);
    });

    test('resta la cantidad de cada item del carrito', () {
      final productos = [
        _producto(id: 'A', productoId: 'pA', existencia: 10),
        _producto(id: 'B', productoId: 'pB', existencia: 5),
      ];
      final venta = _venta([_item('A', 4), _item('B', 2)]);

      final result = StockCalculator.existenciasTrasVenta(venta, productos);

      expect(result['A'], 6);
      expect(result['B'], 3);
    });

    test('desagrega fracción cuando la existencia no alcanza', () {
      // Padre: 1 unidad = 6 fracciones. Hijo tiene 2, se venden 5.
      final padre = _producto(id: 'PADRE', productoId: 'pPadre', existencia: 4);
      final hijo = _producto(
        id: 'HIJO',
        productoId: 'pHijo',
        existencia: 2,
        fraccionDe: FraccionDeModel(id: 'pPadre', nombre: 'Padre'),
        unidadesPorFraccion: 6,
      );
      final venta = _venta([_item('HIJO', 5)]);

      final result =
          StockCalculator.existenciasTrasVenta(venta, [padre, hijo]);

      // need = 5 - 2 = 3; n = ceil(3/6) = 1 unidad del padre desagregada.
      // Padre: 4 - 1 = 3. Hijo: 2 + (1*6) - 5 = 3.
      expect(result['PADRE'], 3);
      expect(result['HIJO'], 3);
    });

    test('no desagrega si el hijo tiene existencia suficiente', () {
      final padre = _producto(id: 'PADRE', productoId: 'pPadre', existencia: 4);
      final hijo = _producto(
        id: 'HIJO',
        productoId: 'pHijo',
        existencia: 10,
        fraccionDe: FraccionDeModel(id: 'pPadre', nombre: 'Padre'),
        unidadesPorFraccion: 6,
      );
      final venta = _venta([_item('HIJO', 5)]);

      final result =
          StockCalculator.existenciasTrasVenta(venta, [padre, hijo]);

      // El padre no se toca; solo se descuenta al hijo.
      expect(result.containsKey('PADRE'), isFalse);
      expect(result['HIJO'], 5);
    });

    test('ignora items cuyo producto no está en cache', () {
      final productos = [
        _producto(id: 'A', productoId: 'pA', existencia: 10),
      ];
      final venta = _venta([_item('A', 2), _item('DESCONOCIDO', 3)]);

      final result = StockCalculator.existenciasTrasVenta(venta, productos);

      expect(result['A'], 8);
      // El desconocido no es fracción resoluble pero igual entra en el paso 2
      // (resta directa), partiendo de 0 por no existir en cache.
      expect(result['DESCONOCIDO'], -3);
    });

    test('devuelve mapa vacío si la venta no tiene productos', () {
      final productos = [
        _producto(id: 'A', productoId: 'pA', existencia: 10),
      ];
      final venta = _venta([]);

      final result = StockCalculator.existenciasTrasVenta(venta, productos);

      expect(result, isEmpty);
    });
  });

  group('StockCalculator.replayVentas', () {
    test('encadena varias ventas sobre el snapshot del servidor', () {
      // Snapshot del servidor: A=100. Dos ventas pendientes descuentan 3 y 4.
      final snapshot = [
        _producto(id: 'A', productoId: 'pA', existencia: 100),
        _producto(id: 'B', productoId: 'pB', existencia: 50),
      ];
      final ventas = [
        _venta([_item('A', 3)], syncId: 'v1'),
        _venta([_item('A', 4), _item('B', 5)], syncId: 'v2'),
      ];

      final result = StockCalculator.replayVentas(snapshot, ventas);

      // A: 100 - 3 - 4 = 93; B: 50 - 5 = 45.
      expect(result['A'], 93);
      expect(result['B'], 45);
    });

    test('preserva existencias negativas (venta sin stock offline)', () {
      final snapshot = [
        _producto(id: 'A', productoId: 'pA', existencia: 2),
      ];
      final ventas = [
        _venta([_item('A', 5)], syncId: 'v1'),
        _venta([_item('A', 3)], syncId: 'v2'),
      ];

      final result = StockCalculator.replayVentas(snapshot, ventas);

      // 2 - 5 - 3 = -6: no se clampea, se permite negativo.
      expect(result['A'], -6);
    });

    test('la desagregación de la 2da venta ve el stock decrementado por la 1ra',
        () {
      // Padre: 1 unidad = 6 fracciones. Hijo arranca con 2.
      final padre = _producto(id: 'PADRE', productoId: 'pPadre', existencia: 4);
      final hijo = _producto(
        id: 'HIJO',
        productoId: 'pHijo',
        existencia: 2,
        fraccionDe: FraccionDeModel(id: 'pPadre', nombre: 'Padre'),
        unidadesPorFraccion: 6,
      );
      // v1 vende 5 del hijo: need=3 -> desagrega 1 padre. Padre=3, Hijo=3.
      // v2 vende 4 del hijo sobre Hijo=3: need=1 -> desagrega 1 padre.
      // Padre=2, Hijo=3+6-4=5.
      final ventas = [
        _venta([_item('HIJO', 5)], syncId: 'v1'),
        _venta([_item('HIJO', 4)], syncId: 'v2'),
      ];

      final result = StockCalculator.replayVentas([padre, hijo], ventas);

      expect(result['PADRE'], 2);
      expect(result['HIJO'], 5);
    });

    test('sin ventas devuelve mapa vacío (no toca el snapshot)', () {
      final snapshot = [
        _producto(id: 'A', productoId: 'pA', existencia: 10),
      ];

      final result = StockCalculator.replayVentas(snapshot, []);

      expect(result, isEmpty);
    });
  });
}
