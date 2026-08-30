import 'package:cuadre_caja_app/core/constants/bill_denominations.dart';
import 'package:cuadre_caja_app/core/utils/currency.dart';
import 'package:cuadre_caja_app/data/models/pago_multimoneda_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CurrencyUtils', () {
    const tasas = {'USD': 400.0, 'MLC': 120.0};

    test('convertToBase y convertFromBase son inversos', () {
      const montoUsd = 5.0;
      final enCup = CurrencyUtils.convertToBase(montoUsd, 'USD', tasas, 'CUP');
      final deVuelta =
          CurrencyUtils.convertFromBase(enCup, 'USD', tasas, 'CUP');
      expect(deVuelta, closeTo(montoUsd, 0.01));
    });

    test('con moneda base USD convierte CUP correctamente', () {
      expect(
        CurrencyUtils.convertToBase(400, 'CUP', tasas, 'USD'),
        closeTo(1, 0.001),
      );
    });

    test('convertToBase con tasa base 0 devuelve 0 (no Infinity)', () {
      const tasasCorruptas = {'USD': 0.0};
      final resultado =
          CurrencyUtils.convertToBase(100, 'USD', tasasCorruptas, 'USD');
      expect(resultado.isFinite, isTrue);
      expect(resultado, 0);
    });

    test('calcularVuelto no devuelve cambio si falta pago', () {
      final vuelto = CurrencyUtils.calcularVuelto(
        totalBase: 1000,
        pagos: const [
          PagoLinea(
            tipo: 'cash',
            moneda: 'CUP',
            monto: 500,
            equivalenteBase: 500,
          ),
        ],
        monedaCobro: 'CUP',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {'CUP': BillDenominations.cup},
      );

      expect(vuelto, isEmpty);
    });
  });
}
