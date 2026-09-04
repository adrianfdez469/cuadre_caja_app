import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/utils/sync_error_messages.dart';

/// El backend rechaza una venta con `code` + `error`. El `code` es el
/// discriminante estable —el contrato dice expresamente que el texto puede
/// cambiar— así que se mira primero y el texto queda de respaldo para una
/// respuesta que no lo traiga.
void main() {
  group('MISSING_EXCHANGE_RATE', () {
    const mensaje =
        'No hay tasa de cambio registrada para USD. Regístrala en '
        'Configuración → Tasas de cambio antes de cobrar en otra moneda.';

    test('se reconoce por el code', () {
      expect(
        SyncErrorMessages.isMissingExchangeRate('MISSING_EXCHANGE_RATE', null),
        isTrue,
      );
      expect(
        SyncErrorMessages.title(null, code: 'MISSING_EXCHANGE_RATE'),
        'Falta una tasa de cambio',
      );
    });

    test('se reconoce por el texto cuando no viene el code', () {
      expect(SyncErrorMessages.isMissingExchangeRate(null, mensaje), isTrue);
      expect(SyncErrorMessages.title(mensaje), 'Falta una tasa de cambio');
    });

    test('es permanente: no vuelve a la cola de reintento automático', () {
      expect(SyncErrorMessages.isPermanent('MISSING_EXCHANGE_RATE'), isTrue);
    });
  });

  group('otros errores', () {
    test('no se confunden con la tasa faltante', () {
      const stock = 'Existencia insuficiente para el producto Café';
      expect(SyncErrorMessages.isMissingExchangeRate(null, stock), isFalse);
      expect(SyncErrorMessages.title(stock), 'Stock insuficiente');
    });

    test('siguen siendo transitorios', () {
      // Un período cerrado se resuelve solo (la venta se mueve y se reintenta):
      // sacarlo de la cola dejaría ventas sin subir.
      expect(SyncErrorMessages.isPermanent(null), isFalse);
      expect(SyncErrorMessages.isPermanent('ALGO_QUE_NO_CONOCEMOS'), isFalse);
    });

    test('un code desconocido no pisa el título deducido del texto', () {
      expect(
        SyncErrorMessages.title(
          'No existe un período abierto en la tienda',
          code: 'ALGO_NUEVO',
        ),
        'No hay período abierto',
      );
    });
  });
}
