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
      ..debugSetActiveCart(CartModel(id: 'c-1', nombre: 'Cuenta #1', items: items));
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

    test('con permitirSinStock entra igual y sube la cantidad', () async {
      final prods = [producto('a'), producto('c', existencia: 1)];
      final (provider, _) = build(
        items: [item('a'), item('b'), item('c', cantidad: 1)],
      );

      final ok = await provider.addToCart(
        producto('c', existencia: 1),
        allProductos: prods,
        permitirSinStock: true,
        moverAlInicio: true,
      );

      expect(ok, isTrue);
      expect(idsDe(provider), ['c', 'a', 'b']);
      expect(provider.activeCart!.items.first.cantidad, 2);
    });

    test('updateItemCantidad supera la existencia solo con permitirSinStock',
        () async {
      final prods = [producto('a', existencia: 2)];
      final (provider, _) = build(items: [item('a', cantidad: 1)]);

      expect(
        await provider.updateItemCantidad(
          0,
          9,
          allProductos: prods,
          producto: prods.first,
        ),
        isFalse,
      );
      expect(provider.activeCart!.items.first.cantidad, 1);

      expect(
        await provider.updateItemCantidad(
          0,
          9,
          allProductos: prods,
          producto: prods.first,
          permitirSinStock: true,
        ),
        isTrue,
      );
      expect(provider.activeCart!.items.first.cantidad, 9);
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

  /// Provider ya inicializado, con la cuenta principal creada por `init()`.
  Future<CartProvider> conCuentas(int cuantas) async {
    final provider = CartProvider(FakeCartLocalDataSource());
    await provider.init('t-1');
    for (var i = 1; i < cuantas; i++) {
      await provider.createNextCart();
    }
    return provider;
  }

  List<String> nombresDe(CartProvider p) =>
      p.carts.map((c) => c.nombre).toList();

  group('nombres de cuenta', () {
    test('init crea la cuenta principal como "Cuenta #1"', () async {
      final provider = await conCuentas(1);

      expect(nombresDe(provider), ['Cuenta #1']);
    });

    test('el consecutivo sigue al mayor existente', () async {
      final provider = await conCuentas(3);

      expect(nombresDe(provider), ['Cuenta #1', 'Cuenta #2', 'Cuenta #3']);
      expect(provider.nextCartName(), 'Cuenta #4');
    });

    test('cerrar una cuenta del medio no reutiliza su número', () async {
      final provider = await conCuentas(3);

      await provider.deleteCart(1); // cierra "Cuenta #2"

      expect(nombresDe(provider), ['Cuenta #1', 'Cuenta #3']);
      // Con el viejo `cartCount + 1` esto daba "Cuenta #3" otra vez.
      expect(provider.nextCartName(), 'Cuenta #4');

      await provider.createNextCart();
      expect(nombresDe(provider), ['Cuenta #1', 'Cuenta #3', 'Cuenta #4']);
    });

    test('los nombres personalizados no participan del consecutivo', () async {
      final provider = await conCuentas(2);
      await provider.renameCart(1, 'Mesa 4');

      expect(provider.nextCartName(), 'Cuenta #2');
    });

    test('la cuenta recién creada queda activa', () async {
      final provider = await conCuentas(2);

      expect(provider.activeCartIndex, 1);
      expect(provider.activeCart!.nombre, 'Cuenta #2');
      expect(provider.activeCart!.isEmpty, isTrue);
    });
  });

  group('cerrar cuenta', () {
    test('cierra una cuenta aunque tenga productos', () async {
      final provider = await conCuentas(2);
      await provider.addToCart(producto('a'));
      expect(provider.activeCart!.isEmpty, isFalse);

      await provider.deleteCart(1);

      expect(nombresDe(provider), ['Cuenta #1']);
    });

    test('nunca cierra la cuenta principal', () async {
      final provider = await conCuentas(2);

      await provider.deleteCart(0);

      expect(nombresDe(provider), ['Cuenta #1', 'Cuenta #2']);
    });

    test('no cierra la última cuenta que queda', () async {
      final provider = await conCuentas(1);

      await provider.deleteCart(0);

      expect(provider.cartCount, 1);
    });
  });

  group('selectFirstNonEmptyCart', () {
    test('salta a la primera cuenta con productos', () async {
      final provider = await conCuentas(3);
      provider.switchCart(1);
      await provider.addToCart(producto('a'));
      provider.switchCart(2); // activa una vacía

      provider.selectFirstNonEmptyCart();

      expect(provider.activeCart!.nombre, 'Cuenta #2');
    });

    test('si ninguna tiene productos se queda en la principal', () async {
      final provider = await conCuentas(3);
      provider.switchCart(2);

      provider.selectFirstNonEmptyCart();

      expect(provider.activeCart!.nombre, 'Cuenta #1');
    });
  });

  group('onPurchaseCompleted', () {
    test('conserva la cuenta principal aunque la hayan renombrado', () async {
      final provider = await conCuentas(2);
      await provider.renameCart(0, 'Mostrador');
      provider.switchCart(0);
      await provider.addToCart(producto('a'));

      await provider.onPurchaseCompleted();

      // Antes se comparaba por el nombre 'Carrito 1', así que renombrar la
      // cuenta principal bastaba para que la venta la borrara.
      expect(nombresDe(provider), ['Mostrador', 'Cuenta #2']);
    });

    test('cierra la cuenta vendida cuando no es la principal', () async {
      final provider = await conCuentas(2);
      await provider.addToCart(producto('a'));

      await provider.onPurchaseCompleted();

      expect(nombresDe(provider), ['Cuenta #1']);
    });
  });
}
