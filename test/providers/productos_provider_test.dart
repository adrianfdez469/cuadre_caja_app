import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/data/models/categoria_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';

import '../fakes/test_fakes.dart';

void main() {
  ProductoModel producto() => ProductoModel(
        id: 'pt-1',
        productoId: 'p-1',
        nombre: 'Refresco',
        precio: 100,
        costo: 50,
        existencia: 10,
      );

  group('ProductosProvider.addCodigoToProducto', () {
    test('la asociación sobrevive a un rebuild posterior (venta)', () async {
      final local = FakeProductosLocalDataSource();
      final sync = FakeSyncService(
        productos: [producto()],
        productosLocal: local,
      );
      final provider = ProductosProvider(sync);
      await provider.loadProductos('tienda-1');

      // Antes de asociar, el código no resuelve.
      expect(provider.findProductByCodigo('7501234'), isNull);

      await provider.addCodigoToProducto(
        'pt-1',
        CodigoProductoModel(id: 'c-1', codigo: '7501234'),
      );
      expect(provider.findProductByCodigo('7501234')?.id, 'pt-1');

      // Una venta dispara _rebuildProductLists desde _rawProductos: antes del
      // fix esto perdía la asociación (solo estaba en _allProductos).
      provider.updateExistenciaLocal('pt-1', 1);
      expect(provider.findProductByCodigo('7501234')?.id, 'pt-1',
          reason: 'el código debe seguir resolviendo tras el rebuild');
    });

    test('persiste el código en la cache local', () async {
      final local = FakeProductosLocalDataSource();
      final sync = FakeSyncService(
        productos: [producto()],
        productosLocal: local,
      );
      final provider = ProductosProvider(sync);
      await provider.loadProductos('tienda-1');

      await provider.addCodigoToProducto(
        'pt-1',
        CodigoProductoModel(id: 'c-1', codigo: '7501234'),
      );

      expect(local.updateCodigosCalls, hasLength(1));
      expect(local.updateCodigosCalls.single.productoTiendaId, 'pt-1');
      expect(local.updateCodigosCalls.single.codigos.map((c) => c.codigo),
          contains('7501234'));
    });
  });

  group('ProductosProvider.applyStockFilter', () {
    ProductoModel agotado() => ProductoModel(
          id: 'pt-2',
          productoId: 'p-2',
          nombre: 'Agua',
          precio: 80,
          costo: 40,
          existencia: 0,
        );

    test('los agotados aparecen al permitir vender sin existencias', () async {
      final sync = FakeSyncService(productos: [producto(), agotado()]);
      final provider = ProductosProvider(sync);
      await provider.loadProductos('tienda-1');

      // Por defecto el catálogo exige stock.
      expect(provider.productos.map((p) => p.id), ['pt-1']);

      provider.applyStockFilter(true);
      expect(provider.productos.map((p) => p.id), ['pt-2', 'pt-1']);

      provider.applyStockFilter(false);
      expect(provider.productos.map((p) => p.id), ['pt-1']);
    });

    test('repetir el mismo valor no notifica', () async {
      final sync = FakeSyncService(productos: [producto()]);
      final provider = ProductosProvider(sync);
      await provider.loadProductos('tienda-1');

      var notificaciones = 0;
      provider.addListener(() => notificaciones++);

      provider.applyStockFilter(false);
      expect(notificaciones, 0);

      provider.applyStockFilter(true);
      expect(notificaciones, 1);
    });
  });

  group('ProductosProvider.searchProductos', () {
    ProductoModel prod({
      required String id,
      required String nombre,
      String? proveedor,
      String? descripcion,
      CategoriaModel? categoria,
      List<CodigoProductoModel> codigos = const [],
    }) =>
        ProductoModel(
          id: id,
          productoId: 'p-$id',
          nombre: nombre,
          descripcion: descripcion,
          precio: 100,
          costo: 50,
          existencia: 10,
          proveedor: proveedor,
          categoria: categoria,
          codigos: codigos,
        );

    Future<ProductosProvider> conCatalogo(List<ProductoModel> productos) async {
      final provider = ProductosProvider(FakeSyncService(productos: productos));
      await provider.loadProductos('tienda-1');
      return provider;
    }

    test('ignora las tildes: "azucar" encuentra "Azúcar"', () async {
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Azúcar morena'),
        prod(id: 'b', nombre: 'Sal'),
      ]);

      provider.searchProductos('azucar');

      expect(provider.productos.map((p) => p.id), ['a']);
    });

    test('ignora las tildes también en la ñ y la diéresis', () async {
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Piña colada'),
        prod(id: 'b', nombre: 'Pingüino helado'),
      ]);

      provider.searchProductos('pina');
      expect(provider.productos.map((p) => p.id), ['a']);

      provider.searchProductos('pinguino');
      expect(provider.productos.map((p) => p.id), ['b']);
    });

    test('busca por palabras sueltas: "coca 2" encuentra "Coca Cola 2L"',
        () async {
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Coca Cola 2L'),
        prod(id: 'b', nombre: 'Coca Cola Zero'),
      ]);

      provider.searchProductos('coca 2');

      expect(provider.productos.map((p) => p.id), ['a']);
    });

    test('el orden de las palabras da igual', () async {
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Coca Cola 2L'),
      ]);

      provider.searchProductos('cola coca');

      expect(provider.productos.map((p) => p.id), ['a']);
    });

    test('busca por proveedor, que se ve en la fila del catálogo', () async {
      // El catálogo pinta "nombre - proveedor": teclear algo visible debe
      // encontrar el producto.
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Coca Cola', proveedor: 'Distr. Sur'),
        prod(id: 'b', nombre: 'Fanta', proveedor: 'Distr. Norte'),
      ]);

      provider.searchProductos('distr sur');

      expect(provider.productos.map((p) => p.id), ['a']);
    });

    test('sigue buscando por descripción y por código (sin regresión)',
        () async {
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Refresco', descripcion: 'botella retornable'),
        prod(
          id: 'b',
          nombre: 'Galleta',
          codigos: [CodigoProductoModel(id: 'c1', codigo: '7501234')],
        ),
      ]);

      provider.searchProductos('retornable');
      expect(provider.productos.map((p) => p.id), ['a']);

      provider.searchProductos('7501234');
      expect(provider.productos.map((p) => p.id), ['b']);
    });

    test('sin resultados devuelve lista vacía', () async {
      final provider = await conCatalogo([prod(id: 'a', nombre: 'Sal')]);

      provider.searchProductos('zzz');

      expect(provider.productos, isEmpty);
    });

    test('vaciar el buscador devuelve el catálogo completo', () async {
      final provider = await conCatalogo([
        prod(id: 'a', nombre: 'Sal'),
        prod(id: 'b', nombre: 'Azúcar'),
      ]);

      provider.searchProductos('sal');
      expect(provider.productos, hasLength(1));

      provider.searchProductos('');
      expect(provider.productos, hasLength(2));
    });

    test('ordena por relevancia: primero lo que empieza por lo tecleado',
        () async {
      final provider = await conCatalogo([
        // Alfabéticamente "Refresco..." iría antes que "Zumo...", y ambos
        // antes no se distinguían del que empieza por la consulta.
        prod(id: 'medio', nombre: 'Refresco sabor coca'),
        prod(id: 'empieza', nombre: 'Coca Cola'),
      ]);

      provider.searchProductos('coca');

      expect(provider.productos.map((p) => p.id), ['empieza', 'medio']);
    });

    test('a igual relevancia el orden es alfabético y estable', () async {
      final provider = await conCatalogo([
        prod(id: 'zero', nombre: 'Coca Cola Zero'),
        prod(id: 'dos', nombre: 'Coca Cola 2L'),
      ]);

      provider.searchProductos('coca');

      // "coca cola 2l" < "coca cola zero"
      expect(provider.productos.map((p) => p.id), ['dos', 'zero']);
    });
  });

  group('ProductosProvider — búsqueda y categoría se aplican juntas', () {
    final bebidas = CategoriaModel(id: 'cat-beb', nombre: 'Bebidas', color: '#111');
    final abarrotes =
        CategoriaModel(id: 'cat-aba', nombre: 'Abarrotes', color: '#222');

    ProductoModel prod(String id, String nombre, CategoriaModel cat) =>
        ProductoModel(
          id: id,
          productoId: 'p-$id',
          nombre: nombre,
          precio: 100,
          costo: 50,
          existencia: 10,
          categoria: cat,
        );

    Future<ProductosProvider> conCatalogo() async {
      final provider = ProductosProvider(FakeSyncService(productos: [
        prod('coca-beb', 'Coca Cola', bebidas),
        prod('fanta-beb', 'Fanta', bebidas),
        prod('coca-aba', 'Coca en polvo', abarrotes),
      ]));
      await provider.loadProductos('tienda-1');
      return provider;
    }

    test('elegir categoría después de buscar respeta la búsqueda', () async {
      // UX-02: antes, tocar la categoría descartaba la búsqueda pero dejaba el
      // texto escrito en el buscador.
      final provider = await conCatalogo();

      provider.searchProductos('coca');
      expect(provider.productos.map((p) => p.id), ['coca-beb', 'coca-aba']);

      provider.filterByCategoria(bebidas.id);
      expect(provider.productos.map((p) => p.id), ['coca-beb']);
    });

    test('buscar después de elegir categoría respeta la categoría', () async {
      final provider = await conCatalogo();

      provider.filterByCategoria(bebidas.id);
      provider.searchProductos('coca');

      expect(provider.productos.map((p) => p.id), ['coca-beb']);
    });

    test('quitar la categoría conserva la búsqueda', () async {
      final provider = await conCatalogo();

      provider.searchProductos('coca');
      provider.filterByCategoria(bebidas.id);
      provider.filterByCategoria(null);

      expect(provider.productos.map((p) => p.id), ['coca-beb', 'coca-aba']);
    });

    test('la búsqueda sobrevive a una venta y a cambiar el filtro de stock',
        () async {
      final provider = await conCatalogo();
      provider.searchProductos('coca');

      provider.updateExistenciaLocal('coca-beb', 1);
      expect(provider.productos.map((p) => p.id), ['coca-beb', 'coca-aba'],
          reason: 'una venta no debe devolver el catálogo completo');

      provider.applyStockFilter(true);
      expect(provider.productos.map((p) => p.id), ['coca-beb', 'coca-aba']);
    });
  });

  group('ProductosProvider — índice de búsqueda', () {
    test('un código recién asociado se vuelve buscable', () async {
      final provider = ProductosProvider(FakeSyncService(
        productos: [
          ProductoModel(
            id: 'pt-1',
            productoId: 'p-1',
            nombre: 'Refresco',
            precio: 100,
            costo: 50,
            existencia: 10,
          ),
        ],
        productosLocal: FakeProductosLocalDataSource(),
      ));
      await provider.loadProductos('tienda-1');

      provider.searchProductos('7501234');
      expect(provider.productos, isEmpty);

      await provider.addCodigoToProducto(
        'pt-1',
        CodigoProductoModel(id: 'c-1', codigo: '7501234'),
      );

      expect(provider.productos.map((p) => p.id), ['pt-1'],
          reason: 'el índice debe reconstruirse al asociar el código');
    });
  });

  group('ProductosProvider.refreshFromLocalCache', () {
    // Es el repintado que corre tras cada sincronización desde que el callback
    // dejó de ir a la red: si no reconstruye las listas, el POS mostraría
    // existencias viejas tras cada venta.
    test('reconstruye el catálogo desde la base local', () async {
      final provider = ProductosProvider(FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      ));

      await provider.refreshFromLocalCache('tienda-1');

      expect(provider.allProductos.map((p) => p.id), ['pt-1']);
    });

    test('deja el catálogo buscable', () async {
      final provider = ProductosProvider(FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      ));

      await provider.refreshFromLocalCache('tienda-1');
      provider.searchProductos('Refresco');

      expect(provider.productos.map((p) => p.id), ['pt-1']);
    });

    test('notifica a los oyentes', () async {
      final provider = ProductosProvider(FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      ));
      var notificaciones = 0;
      provider.addListener(() => notificaciones++);

      await provider.refreshFromLocalCache('tienda-1');

      expect(notificaciones, greaterThanOrEqualTo(1));
    });
  });

  group('ProductosProvider.tieneCatalogoLocal', () {
    test('sin cargar nada, no hay catálogo con el que arrancar', () {
      final provider = ProductosProvider(FakeSyncService());

      expect(provider.tieneCatalogoLocal, isFalse);
    });

    test('tras cargar, hay catálogo', () async {
      final provider = ProductosProvider(FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      ));

      await provider.refreshFromLocalCache('tienda-1');

      expect(provider.tieneCatalogoLocal, isTrue);
    });

    test('mira la lista cruda, no la filtrada por stock', () async {
      // Un catálogo entero agotado deja `allProductos` vacío cuando no se
      // permite vender sin existencias, pero sí hay con qué arrancar el POS.
      final provider = ProductosProvider(FakeSyncService(
        productos: [
          ProductoModel(
            id: 'pt-1',
            productoId: 'p-1',
            nombre: 'Agotado',
            precio: 100,
            costo: 50,
            existencia: 0,
          ),
        ],
        productosLocal: FakeProductosLocalDataSource(),
      ));

      await provider.refreshFromLocalCache('tienda-1');

      expect(provider.allProductos, isEmpty,
          reason: 'por defecto no se listan los agotados');
      expect(provider.tieneCatalogoLocal, isTrue);
    });
  });

  group('ProductosProvider — el repintado tras sync no vuelve a la red', () {
    // Es el objetivo entero de la reestructuración: onDataRefreshed repinta
    // desde SQLite, porque quien habló con el servidor fue fullSync.
    test('refreshFromLocalCache lee de disco y no llama a loadProductos',
        () async {
      final sync = FakeSyncService(
        productos: [producto()],
        productosEnCacheLocal: [
          ProductoModel(
            id: 'pt-local',
            productoId: 'p-local',
            nombre: 'Solo en disco',
            precio: 100,
            costo: 50,
            existencia: 3,
          ),
        ],
        productosLocal: FakeProductosLocalDataSource(),
      );
      final provider = ProductosProvider(sync);

      await provider.refreshFromLocalCache('tienda-1');

      expect(provider.allProductos.map((p) => p.id), ['pt-local']);
      expect(sync.loadProductosCalls, 0, reason: 'cero GET /productos');
      expect(sync.loadProductosLocalOnlyCalls, 1);
    });

    test('loadProductos sí va a la red (contraste del test anterior)',
        () async {
      final sync = FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      );
      final provider = ProductosProvider(sync);

      await provider.loadProductos('tienda-1');

      expect(sync.loadProductosCalls, 1);
      expect(sync.loadProductosLocalOnlyCalls, 0);
    });

    test('refreshFromLocalCache no toca isLoading', () async {
      // Corre tras cada sincronización: mover isLoading pondría el catálogo en
      // spinner cada vez que se vende algo.
      final sync = FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      );
      final provider = ProductosProvider(sync);

      await provider.refreshFromLocalCache('tienda-1');

      expect(provider.isLoading, isFalse);
    });

    test('el repintado conserva la búsqueda activa', () async {
      final sync = FakeSyncService(
        productos: [producto()],
        productosLocal: FakeProductosLocalDataSource(),
      );
      final provider = ProductosProvider(sync);
      await provider.loadProductos('tienda-1');
      provider.searchProductos('nada-que-coincida');
      expect(provider.productos, isEmpty);

      await provider.refreshFromLocalCache('tienda-1');

      expect(provider.productos, isEmpty,
          reason: 'un refresco no puede devolver el catálogo completo bajo '
              'el cajero mientras busca');
      expect(provider.query, 'nada-que-coincida');
    });
  });
}
