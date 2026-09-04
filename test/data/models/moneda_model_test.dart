import 'package:flutter_test/flutter_test.dart';

import '../../helpers/payment_test_harness.dart';

/// Las tasas están ancladas en CUP, así que convertir a la moneda base pasa por
/// CUP y necesita la tasa CUP de la propia base. Si falta, `cupTasa(monedaBase)`
/// cae a 1 y toda conversión queda inflada por el factor de la base: un cobro de
/// 1360 CUP en un negocio con base USD se registraría como 1360 USD. El backend
/// rechaza esa venta con `MISSING_EXCHANGE_RATE`, así que la app no debe
/// llegar a ofrecerla.
void main() {
  group('base distinta de CUP sin su propia tasa', () {
    final config = buildTestConfig(
      monedaBase: 'USD',
      tasas: const {'EUR': 775},
      monedasAlternativas: const ['EUR'],
    );

    test('no se puede convertir a base', () {
      expect(config.puedeConvertirABase, isFalse);
    });

    test('no ofrece monedas alternativas', () {
      expect(config.monedasAlternativas(), isEmpty);
      expect(config.hasMonedasAlternativas, isFalse);
    });

    test('sigue dejando cobrar en la moneda base', () {
      // Una venta cobrada íntegramente en la base no necesita ninguna tasa: la
      // conversión se cancela. Bloquearla también dejaría la caja sin vender.
      expect(config.monedasCobrables(), const ['USD']);
    });
  });

  group('base distinta de CUP con su tasa', () {
    final config = buildTestConfig(
      monedaBase: 'USD',
      tasas: const {'USD': 680, 'EUR': 775},
      monedasAlternativas: const ['EUR'],
    );

    test('ofrece la base y las alternativas convertibles', () {
      expect(config.puedeConvertirABase, isTrue);
      expect(config.monedasCobrables(), const ['USD', 'EUR']);
    });
  });

  group('base CUP', () {
    test('CUP es el ancla: nunca necesita una tasa propia', () {
      final config = buildTestConfig(
        monedaBase: 'CUP',
        tasas: const {'USD': 400, 'MLC': 120},
        monedasAlternativas: const ['USD', 'MLC'],
      );

      expect(config.puedeConvertirABase, isTrue);
      expect(config.monedasCobrables(), const ['CUP', 'USD', 'MLC']);
    });

    test('una alternativa sin tasa no se ofrece', () {
      final config = buildTestConfig(
        monedaBase: 'CUP',
        tasas: const {'USD': 400},
        monedasAlternativas: const ['USD', 'MLC'],
      );

      expect(config.monedasCobrables(), const ['CUP', 'USD']);
    });
  });
}
