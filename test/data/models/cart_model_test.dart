import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/utils/formatters.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';

CartItemModel _item(String nombre, double cantidad) => CartItemModel(
      productoTiendaId: 'pt-$nombre',
      nombre: nombre,
      precio: 100,
      cantidad: cantidad,
    );

void main() {
  group('CartModel.unidadesCount', () {
    test('cuenta unidades reales, no líneas distintas', () {
      final cart = CartModel(
        id: 'c1',
        nombre: 'Carrito 1',
        items: [_item('arroz', 3), _item('azucar', 2)],
      );

      expect(cart.itemCount, 2, reason: 'son 2 tipos de producto');
      expect(cart.unidadesCount, 5, reason: 'pero 5 unidades en total');
    });

    test('varias unidades de un solo producto cuentan todas', () {
      final cart = CartModel(
        id: 'c1',
        nombre: 'Carrito 1',
        items: [_item('agua', 12)],
      );

      expect(cart.itemCount, 1);
      expect(cart.unidadesCount, 12);
    });

    test('suma cantidades fraccionarias (productos por peso)', () {
      final cart = CartModel(
        id: 'c1',
        nombre: 'Carrito 1',
        items: [_item('queso', 0.5), _item('jamon', 1.25)],
      );

      expect(cart.unidadesCount, 1.75);
    });

    test('carrito vacío', () {
      expect(CartModel(id: 'c1', nombre: 'Carrito 1').unidadesCount, 0);
    });
  });

  group('Formatters.formatUnidades', () {
    test('usa singular solo con exactamente una unidad', () {
      expect(Formatters.formatUnidades(1), '1 artículo');
      expect(Formatters.formatUnidades(0), '0 artículos');
      expect(Formatters.formatUnidades(2), '2 artículos');
    });

    test('no muestra decimales cuando la cantidad es entera', () {
      expect(Formatters.formatUnidades(12), '12 artículos');
    });

    test('muestra un decimal cuando la cantidad es fraccionaria', () {
      expect(Formatters.formatUnidades(1.75), '1.8 artículos');
      expect(Formatters.formatUnidades(0.5), '0.5 artículos');
    });
  });
}
