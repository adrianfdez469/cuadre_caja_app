import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';

import '../fakes/test_fakes.dart';

void main() {
  ProductoModel producto(
    String id, {
    String? nombre,
    double existencia = 100,
  }) =>
      ProductoModel(
        id: id,
        productoId: 'p-$id',
        nombre: nombre ?? id.toUpperCase(),
        precio: 100,
        costo: 50,
        existencia: existencia,
      );

  CartItemModel item(String id, {double cantidad = 1}) => CartItemModel(
        productoTiendaId: id,
        nombre: id.toUpperCase(),
        precio: 100,
        cantidad: cantidad,
      );

  /// Provider con un carrito activo preconfigurado.
  (CartProvider, FakeCartLocalDataSource) build({List<CartItemModel>? items}) {
    final local = FakeCartLocalDataSource();
    final provider = CartProvider(local)
      ..debugSetActiveCart(CartModel(id: 'c-1', nombre: 'Carrito 1', items: items));
    return (provider, local);
  }

  List<String> idsDe(CartProvider p) =>
      p.activeCart!.items.map((i) => i.productoTiendaId).toList();

  group('addToCart con moverAlInicio', () {
    test('producto nuevo se inserta en la posición 0', () async {
      final (provider, _) = build(items: [item('a'), item('b')]);

      final ok = await provider.addToCart(producto('c'), moverAlInicio: true);

      expect(ok, isTrue);
      expect(idsDe(provider), ['c', 'a', 'b']);
    });

    test('producto existente suma cantidad, no duplica y sube al tope', () async {
      final (provider, _) = build(
        items: [item('a'), item('b'), item('c', cantidad: 2)],
      );

      final ok = await provider.addToCart(producto('c'), moverAlInicio: true);

      expect(ok, isTrue);
      // Conserva el orden relativo del resto.
      expect(idsDe(provider), ['c', 'a', 'b']);
      expect(provider.activeCart!.items.length, 3);
      expect(provider.activeCart!.items.first.cantidad, 3);
    });

    test('producto ya en la posición 0 es idempotente en el orden', () async {
      final (provider, _) = build(items: [item('a'), item('b'), item('c')]);

      await provider.addToCart(producto('a'), moverAlInicio: true);

      expect(idsDe(provider), ['a', 'b', 'c']);
      expect(provider.activeCart!.items.first.cantidad, 2);
    });

    test('el orden nuevo se persiste', () async {
      final (provider, local) = build(items: [item('a'), item('b')]);

      await provider.addToCart(producto('c'), moverAlInicio: true);

      expect(local.updateCalls, isNotEmpty);
      expect(
        local.updateCalls.last.items.map((i) => i.productoTiendaId).toList(),
        ['c', 'a', 'b'],
      );
    });
  });

  group('addToCart sin moverAlInicio (regresión: flujos táctiles)', () {
    test('producto existente conserva su posición', () async {
      final (provider, _) = build(
        items: [item('a'), item('b'), item('c', cantidad: 2)],
      );

      await provider.addToCart(producto('c'));

      expect(idsDe(provider), ['a', 'b', 'c']);
      expect(provider.activeCart!.items.last.cantidad, 3);
    });

    test('producto nuevo se añade al final', () async {
      final (provider, _) = build(items: [item('a'), item('b')]);

      await provider.addToCart(producto('c'));

      expect(idsDe(provider), ['a', 'b', 'c']);
    });
  });

  group('addToCart rechazado por stock', () {
    test('devuelve false y no reordena ni muta', () async {
      final prods = [producto('a'), producto('c', existencia: 1)];
      final (provider, _) = build(
        items: [item('a'), item('b'), item('c', cantidad: 1)],
      );

      // 'c' tiene existencia 1 y ya hay 1 en el carrito → máximo 0.
      final ok = await provider.addToCart(
        producto('c', existencia: 1),
        allProductos: prods,
        moverAlInicio: true,
      );

      expect(ok, isFalse);
      expect(idsDe(provider), ['a', 'b', 'c']);
      expect(provider.activeCart!.items.last.cantidad, 1);
    });
  });

  group('mutación por id', () {
    test('updateItemCantidadById apunta al producto correcto tras un reorden',
        () async {
      final (provider, _) = build(items: [item('a'), item('b'), item('c')]);

      // Un escaneo reordena: 'c' pasa del índice 2 al 0.
      await provider.addToCart(producto('c'), moverAlInicio: true);
      expect(idsDe(provider), ['c', 'a', 'b']);

      // Un tap capturado antes del reorden apuntaría al índice 2 ('b' ahora),
      // pero al mutar por id se actualiza 'c'.
      final ok = await provider.updateItemCantidadById('c', 7);

      expect(ok, isTrue);
      expect(provider.activeCart!.items.first.productoTiendaId, 'c');
      expect(provider.activeCart!.items.first.cantidad, 7);
      expect(
        provider.activeCart!.items
            .firstWhere((i) => i.productoTiendaId == 'b')
            .cantidad,
        1,
      );
    });

    test('removeItemById elimina la línea correcta', () async {
      final (provider, _) = build(items: [item('a'), item('b'), item('c')]);

      await provider.removeItemById('b');

      expect(idsDe(provider), ['a', 'c']);
    });

    test('id inexistente: false / no-op sin excepción', () async {
      final (provider, _) = build(items: [item('a')]);

      expect(await provider.updateItemCantidadById('zzz', 5), isFalse);
      await provider.removeItemById('zzz');
      expect(idsDe(provider), ['a']);
    });

    test('indexOfProducto sin carrito activo devuelve -1', () {
      final provider = CartProvider(FakeCartLocalDataSource());

      expect(provider.indexOfProducto('a'), -1);
    });
  });

  group('invariante de orden: solo el escaneo reordena', () {
    test('editar cantidades y eliminar no mueve ninguna línea', () async {
      final (provider, _) = build(items: [item('a'), item('b'), item('c')]);

      await provider.updateItemCantidadById('b', 5);
      await provider.updateItemCantidadById('b', 2);
      expect(idsDe(provider), ['a', 'b', 'c']);

      await provider.removeItemById('a');
      expect(idsDe(provider), ['b', 'c']);
    });

    test('updateItemCantidadById a 0 elimina la línea', () async {
      final (provider, _) = build(items: [item('a'), item('b')]);

      await provider.updateItemCantidadById('a', 0);

      expect(idsDe(provider), ['b']);
    });
  });
}
