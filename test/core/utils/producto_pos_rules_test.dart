import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/utils/producto_pos_rules.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';

/// Cubre el flag `permitirSinStock`, que hoy se activa tanto sin conexión como
/// con el ajuste "Vender sin existencias" (ver `VentaSinStockPolicy`).
void main() {
  ProductoModel normal({double existencia = 10, double precio = 100}) =>
      ProductoModel(
        id: 'pt-1',
        productoId: 'p-1',
        nombre: 'Refresco',
        precio: precio,
        costo: 50,
        existencia: existencia,
      );

  ProductoModel caja({double existencia = 0}) => ProductoModel(
        id: 'pt-caja',
        productoId: 'p-caja',
        nombre: 'Caja de refrescos',
        precio: 1000,
        costo: 500,
        existencia: existencia,
      );

  ProductoModel fraccion({double existencia = 0, int unidades = 12}) =>
      ProductoModel(
        id: 'pt-frac',
        productoId: 'p-frac',
        nombre: 'Refresco suelto',
        precio: 100,
        costo: 50,
        existencia: existencia,
        fraccionDe: FraccionDeModel(id: 'p-caja', nombre: 'Caja de refrescos'),
        unidadesPorFraccion: unidades,
      );

  group('getMaxQuantity', () {
    test('exigiendo stock, el máximo es la existencia real', () {
      final p = normal(existencia: 3);
      expect(ProductoPosRules.getMaxQuantity(p, [p]), 3);
    });

    test('agotado y exigiendo stock, no queda nada por vender', () {
      final p = normal(existencia: 0);
      expect(ProductoPosRules.getMaxQuantity(p, [p]), 0);
    });

    test('permitiendo vender sin stock, el producto normal no tiene tope', () {
      final p = normal(existencia: 0);
      expect(
        ProductoPosRules.getMaxQuantity(p, [p], permitirSinStock: true),
        double.infinity,
      );
    });

    test('la existencia negativa tampoco frena la venta', () {
      final p = normal(existencia: -5);
      expect(
        ProductoPosRules.getMaxQuantity(p, [p], permitirSinStock: true),
        double.infinity,
      );
      expect(ProductoPosRules.getMaxQuantity(p, [p]), 0);
    });

    test('la fracción conserva el tope de unidades por caja', () {
      final f = fraccion(unidades: 12);
      final productos = [f, caja()];
      // Sin stock de caja ni de sueltas: exigiendo stock no hay nada; con el
      // permiso, el tope sigue siendo upf - 1 y NO infinito.
      expect(ProductoPosRules.getMaxQuantity(f, productos), 0);
      expect(
        ProductoPosRules.getMaxQuantity(f, productos, permitirSinStock: true),
        11,
      );
    });

    test('lo ya puesto en el carrito descuenta del tope de la fracción', () {
      final f = fraccion(unidades: 12);
      final productos = [f, caja()];
      expect(
        ProductoPosRules.getMaxQuantity(
          f,
          productos,
          cantidadEnCarrito: 4,
          permitirSinStock: true,
        ),
        7,
      );
    });
  });

  group('puedeAgregar', () {
    test('agotado: no exigiendo stock sí, exigiéndolo no', () {
      final p = normal(existencia: 0);
      expect(ProductoPosRules.puedeAgregar(p, [p]), isFalse);
      expect(
        ProductoPosRules.puedeAgregar(p, [p], permitirSinStock: true),
        isTrue,
      );
    });

    test('la fracción se corta al llegar al tope aunque se permita sin stock', () {
      final f = fraccion(unidades: 12);
      final productos = [f, caja()];
      expect(
        ProductoPosRules.puedeAgregar(
          f,
          productos,
          cantidadEnCarrito: 11,
          permitirSinStock: true,
        ),
        isFalse,
      );
    });
  });

  group('debeMostrarEnPos', () {
    test('el agotado solo se lista si se permite venderlo', () {
      final p = normal(existencia: 0);
      expect(ProductoPosRules.debeMostrarEnPos(p, [p]), isFalse);
      expect(
        ProductoPosRules.debeMostrarEnPos(p, [p], permitirSinStock: true),
        isTrue,
      );
    });

    test('sin precio no se lista ni permitiendo vender sin stock', () {
      final p = normal(existencia: 0, precio: 0);
      expect(
        ProductoPosRules.debeMostrarEnPos(p, [p], permitirSinStock: true),
        isFalse,
      );
    });

    test('filtrarYOrdenarParaPos deja fuera los agotados al exigir stock', () {
      final conStock = normal(existencia: 5);
      final agotado = caja(existencia: 0);
      final productos = [conStock, agotado];
      expect(
        ProductoPosRules.filtrarYOrdenarParaPos(productos).map((p) => p.id),
        ['pt-1'],
      );
      expect(
        ProductoPosRules.filtrarYOrdenarParaPos(
          productos,
          permitirSinStock: true,
        ).map((p) => p.id),
        // Orden alfabético: "Caja de refrescos" antes que "Refresco".
        ['pt-caja', 'pt-1'],
      );
    });
  });

  group('textos de stock', () {
    test('el diálogo avisa que la venta sin stock se validará al sincronizar', () {
      final p = normal(existencia: 0);
      expect(
        ProductoPosRules.textoStockEnDialogo(p, [p], permitirSinStock: true),
        'Sin stock — se validará al sincronizar',
      );
    });

    test('exigiendo stock, el diálogo muestra los disponibles', () {
      final p = normal(existencia: 7);
      expect(
        ProductoPosRules.textoStockEnDialogo(p, [p]),
        'Disponibles: 7',
      );
    });
  });
}
