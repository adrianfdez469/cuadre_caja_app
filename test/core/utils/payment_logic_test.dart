import 'package:cuadre_caja_app/core/constants/bill_denominations.dart';
import 'package:cuadre_caja_app/core/utils/currency.dart';
import 'package:cuadre_caja_app/core/utils/payment_logic.dart';
import 'package:cuadre_caja_app/data/models/pago_multimoneda_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tasas = {'USD': 400.0, 'MLC': 120.0, 'EUR': 440.0};
  const cupDenoms = BillDenominations.cup;

  group('PaymentLogic.buildPagosLinea', () {
    test('genera líneas separadas de efectivo y transferencia', () {
      final pagos = {
        'CUP': const PagoMonedaState(cash: 500, transfer: 300, transferDestId: 'd1'),
      };

      final lineas = PaymentLogic.buildPagosLinea(pagos, 'CUP', tasas);

      expect(lineas, hasLength(2));
      expect(lineas[0].tipo, 'cash');
      expect(lineas[0].monto, 500);
      expect(lineas[1].tipo, 'transfer');
      expect(lineas[1].monto, 300);
      expect(lineas[1].transferDestinationId, 'd1');
    });

    test('convierte montos a moneda base USD', () {
      final pagos = {
        'CUP': const PagoMonedaState(cash: 400),
      };

      final lineas = PaymentLogic.buildPagosLinea(pagos, 'USD', tasas);

      expect(lineas.single.equivalenteBase, 1);
    });
  });

  group('PaymentLogic.falta y vuelto', () {
    test('pago exacto en CUP no genera falta ni vuelto', () {
      final pagos = {'CUP': const PagoMonedaState(cash: 1500)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);

      expect(PaymentLogic.falta(1500, pagado), isFalse);
      expect(
        PaymentLogic.vueltoTotalBase(
          total: 1500,
          totalPagadoBase: pagado,
          falta: false,
        ),
        0,
      );
    });

    test('sobrepago genera vuelto correcto', () {
      final pagos = {'CUP': const PagoMonedaState(cash: 2000)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);

      expect(PaymentLogic.falta(1500, pagado), isFalse);
      expect(
        PaymentLogic.vueltoTotalBase(
          total: 1500,
          totalPagadoBase: pagado,
          falta: false,
        ),
        500,
      );
    });

    test('pago insuficiente marca falta y anula vuelto', () {
      final pagos = {'CUP': const PagoMonedaState(cash: 900)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);
      final falta = PaymentLogic.falta(1500, pagado);

      expect(falta, isTrue);
      expect(
        PaymentLogic.vueltoTotalBase(
          total: 1500,
          totalPagadoBase: pagado,
          falta: falta,
        ),
        0,
      );
    });
  });

  group('PaymentLogic.applyMixedTransferEdit', () {
    test('al agregar transferencia reduce efectivo manteniendo total', () {
      final result = PaymentLogic.applyMixedTransferEdit(
        currentCash: 1000,
        currentTransfer: 0,
        newTransfer: 300,
      );

      expect(result.cash, 700);
      expect(result.transfer, 300);
      expect(result.cash + result.transfer, 1000);
    });

    test('no deja efectivo negativo', () {
      final result = PaymentLogic.applyMixedTransferEdit(
        currentCash: 200,
        currentTransfer: 0,
        newTransfer: 500,
      );

      expect(result.cash, 0);
      expect(result.transfer, 500);
    });
  });

  group('PaymentLogic.collapseTransferToCash', () {
    test('al ocultar transferencia suma al efectivo', () {
      final result = PaymentLogic.collapseTransferToCash(
        cash: 700,
        transfer: 300,
      );

      expect(result.cash, 1000);
      expect(result.transfer, 0);
    });
  });

  group('PaymentLogic multimoneda', () {
    test('pago en USD con base CUP cuadra total', () {
      const total = 1200.0;
      final pagos = {'USD': const PagoMonedaState(cash: 3)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);

      expect(pagado, 1200);
      expect(PaymentLogic.falta(total, pagado), isFalse);
    });

    test('combinación CUP + MLC cubre el total', () {
      const total = 1500.0;
      final pagos = {
        'CUP': const PagoMonedaState(cash: 300),
        'MLC': const PagoMonedaState(cash: 10),
      };
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);

      expect(pagado, 1500);
      expect(PaymentLogic.falta(total, pagado), isFalse);
    });

    test('suggestCash calcula restante en otra moneda', () {
      const total = 1500.0;
      final pagos = {
        'CUP': const PagoMonedaState(cash: 300),
      };

      final sugerido = PaymentLogic.suggestCash(
        total: total,
        pagos: pagos,
        moneda: 'MLC',
        monedaBase: 'CUP',
        tasas: tasas,
        excludeMoneda: 'MLC',
      );

      expect(sugerido, 10);
    });

    test('moneda base USD: pago en CUP se convierte correctamente', () {
      const total = 10.0;
      final pagos = {'CUP': const PagoMonedaState(cash: 4000)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'USD', tasas);

      expect(pagado, 10);
      expect(PaymentLogic.falta(total, pagado), isFalse);
    });
  });

  group('PaymentLogic.canConfirm', () {
    List<PagoLinea> lineas(Map<String, PagoMonedaState> pagos, String base) =>
        PaymentLogic.buildPagosLinea(pagos, base, tasas);

    test('rechaza si falta monto', () {
      final pagos = {'CUP': const PagoMonedaState(cash: 100)};
      expect(
        PaymentLogic.canConfirm(
          total: 1000,
          falta: true,
          totalPagadoBase: 100,
          pagosLinea: lineas(pagos, 'CUP'),
          hasPagos: true,
        ),
        isFalse,
      );
    });

    test('rechaza transferencia sin destino', () {
      final pagos = {'CUP': const PagoMonedaState(transfer: 1000)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);
      expect(
        PaymentLogic.canConfirm(
          total: 1000,
          falta: false,
          totalPagadoBase: pagado,
          pagosLinea: lineas(pagos, 'CUP'),
          hasPagos: true,
        ),
        isFalse,
      );
    });

    test('acepta pago mixto con destino de transferencia', () {
      final pagos = {
        'CUP': const PagoMonedaState(
          cash: 400,
          transfer: 600,
          transferDestId: 'banco',
        ),
      };
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);
      expect(
        PaymentLogic.canConfirm(
          total: 1000,
          falta: false,
          totalPagadoBase: pagado,
          pagosLinea: lineas(pagos, 'CUP'),
          hasPagos: true,
        ),
        isTrue,
      );
    });
  });

  group('PaymentLogic.calcularVueltoAuto', () {
    test('vuelto en moneda base redondea a denominación mínima', () {
      const total = 1000.0;
      final pagos = [
        PagoLinea(
          tipo: 'cash',
          moneda: 'CUP',
          monto: 1500,
          equivalenteBase: 1500,
        ),
      ];

      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: total,
        pagos: pagos,
        monedaCobro: 'CUP',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {'CUP': cupDenoms},
      );

      expect(vuelto.single.moneda, 'CUP');
      expect(vuelto.single.monto, 500);
    });

    test('vuelto con cobro en USD devuelve cambio en USD y resto en CUP', () {
      const total = 1000.0;
      final pagos = [
        PagoLinea(
          tipo: 'cash',
          moneda: 'USD',
          monto: 5,
          equivalenteBase: 2000,
        ),
      ];

      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: total,
        pagos: pagos,
        monedaCobro: 'USD',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {
          'CUP': cupDenoms,
          'USD': [100, 50, 20, 10, 5, 1],
        },
      );

      expect(vuelto, isNotEmpty);
      final totalVueltoBase = vuelto.fold<double>(
        0,
        (s, v) =>
            s + CurrencyUtils.convertToBase(v.monto, v.moneda, tasas, 'CUP'),
      );
      expect(totalVueltoBase, greaterThanOrEqualTo(1000));
    });
  });
}
