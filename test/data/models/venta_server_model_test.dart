import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';

void main() {
  group('VentaServerModel cache round-trip (toJson -> fromJson)', () {
    VentaServerModel base({
      String? transferDestinationId,
      String? transferDestinationNombre,
    }) {
      return VentaServerModel(
        id: 'venta-1',
        tiendaId: 'tienda-1',
        usuarioId: 'user-1',
        cierrePeriodoId: 'periodo-1',
        total: 1000,
        totalcash: 0,
        totaltransfer: 1000,
        createdAt: DateTime.parse('2026-07-18T10:00:00.000Z'),
        productos: [
          VentaProducto(
            productoTiendaId: 'pt-1',
            cantidad: 2,
            name: 'Producto',
            precio: 500,
          ),
        ],
        transferDestinationId: transferDestinationId,
        transferDestinationNombre: transferDestinationNombre,
      );
    }

    test('preserva el destino de transferencia (id + nombre) al cachear', () {
      final original = base(
        transferDestinationId: 'dest-9',
        transferDestinationNombre: 'Banco X',
      );

      // Simula el ciclo real del cache: jsonEncode(toJson) -> fromJson(decode).
      final restored = VentaServerModel.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.transferDestinationId, 'dest-9');
      expect(restored.transferDestinationNombre, 'Banco X');
      expect(restored.totaltransfer, 1000);
    });

    test('sin destino de transferencia el round-trip deja los campos en null',
        () {
      final original = base();
      final map = original.toJson();
      expect(map.containsKey('transferDestination'), isFalse);

      final restored = VentaServerModel.fromJson(
        jsonDecode(jsonEncode(map)) as Map<String, dynamic>,
      );
      expect(restored.transferDestinationId, isNull);
      expect(restored.transferDestinationNombre, isNull);
    });
  });
}
