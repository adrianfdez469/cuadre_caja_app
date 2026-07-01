import 'package:cuadre_caja_app/core/constants/bill_denominations.dart';
import 'package:cuadre_caja_app/core/utils/cash_amount_input_formatter.dart';
import 'package:cuadre_caja_app/core/utils/currency.dart';
import 'package:cuadre_caja_app/data/models/pago_multimoneda_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashAmountInputFormatter', () {
    const formatter = CashAmountInputFormatter();

    TextEditingValue format(String oldText, String newText) {
      return formatter.formatEditUpdate(
        TextEditingValue(text: oldText),
        TextEditingValue(text: newText),
      );
    }

    test('acepta solo dígitos enteros', () {
      expect(format('', '1500').text, '1500');
    });

    test('elimina decimales al escribir', () {
      expect(format('100', '100.50').text, '100');
    });

    test('elimina caracteres no numéricos', () {
      expect(format('', '1a2b3').text, '123');
    });
  });

  group('formatCashDisplay', () {
    test('muestra enteros sin decimales', () {
      expect(formatCashDisplay(1500), '1500');
      expect(formatCashDisplay(19), '19');
    });

    test('trunca decimales al mostrar', () {
      expect(formatCashDisplay(18.6), '18');
    });

    test('cero devuelve cadena vacía', () {
      expect(formatCashDisplay(0), '');
    });
  });

  group('parseCashAmount', () {
    test('parsea enteros', () {
      expect(parseCashAmount('1500'), 1500);
    });

    test('ignora parte decimal', () {
      expect(parseCashAmount('1500.75'), 1500);
    });

    test('vacío devuelve cero', () {
      expect(parseCashAmount(''), 0);
    });
  });

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
