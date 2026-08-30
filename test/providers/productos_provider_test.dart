import 'package:flutter_test/flutter_test.dart';
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
}
