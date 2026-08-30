import 'package:cuadre_caja_app/core/constants/bill_denominations.dart';
import 'package:cuadre_caja_app/core/utils/currency.dart';
import 'package:cuadre_caja_app/core/utils/payment_logic.dart';
import 'package:cuadre_caja_app/data/models/pago_multimoneda_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
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

  group('PaymentLogic.ceilCash', () {
    test('redondea hacia arriba un total con céntimos', () {
      // El caso del bug: total 3.25 debe predefinir efectivo en 4, no en 3.
      expect(PaymentLogic.ceilCash(3.25), 4);
    });

    test('deja intacto un total entero', () {
      expect(PaymentLogic.ceilCash(3), 3);
    });

    test('no sube un entero con ruido de coma flotante', () {
      expect(PaymentLogic.ceilCash(0.1 + 0.2 + 2.7), 3);
    });

    test('devuelve 0 para montos no positivos', () {
      expect(PaymentLogic.ceilCash(0), 0);
      expect(PaymentLogic.ceilCash(-5), 0);
    });
  });

  group('PaymentLogic.applyMixedTransferEdit', () {
    test('al agregar transferencia reduce efectivo manteniendo total', () {
      final result = PaymentLogic.applyMixedTransferEdit(
        currentCash: 1000,
        currentTransfer: 0,
        newTransfer: 400,
      );

      expect(result.cash, 600);
      expect(result.transfer, 400);
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
    test('al quitar transferencia suma al efectivo', () {
      final result = PaymentLogic.collapseTransferToCash(
        cash: 600,
        transfer: 400,
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

    test('suggestCash redondea hacia arriba en moneda secundaria', () {
      const total = 10000.0;
      const tasasMultimoneda = {'USD': 500.0, 'EUR': 600.0, 'CUP': 1.0};
      final pagos = {'CUP': const PagoMonedaState(cash: 700)};

      final usd = PaymentLogic.suggestCash(
        total: total,
        pagos: pagos,
        moneda: 'USD',
        monedaBase: 'CUP',
        tasas: tasasMultimoneda,
      );

      expect(usd, 19);
    });

    test('suggestCash con varias monedas ya pagadas redondea hacia arriba', () {
      const total = 10000.0;
      const tasasMultimoneda = {'USD': 500.0, 'EUR': 600.0, 'CUP': 1.0};
      final pagos = {
        'CUP': const PagoMonedaState(cash: 700),
        'USD': const PagoMonedaState(cash: 16),
      };

      final eur = PaymentLogic.suggestCash(
        total: total,
        pagos: pagos,
        moneda: 'EUR',
        monedaBase: 'CUP',
        tasas: tasasMultimoneda,
      );

      expect(eur, 3);
    });

    test('escenario multimoneda genera vuelto en moneda base', () {
      const total = 10000.0;
      const tasasMultimoneda = {'USD': 500.0, 'EUR': 600.0, 'CUP': 1.0};
      final pagos = {
        'CUP': const PagoMonedaState(cash: 700),
        'USD': const PagoMonedaState(cash: 16),
        'EUR': const PagoMonedaState(cash: 3),
      };
      final pagado =
          PaymentLogic.totalPagadoBase(pagos, 'CUP', tasasMultimoneda);

      expect(pagado, 10500);
      expect(
        PaymentLogic.vueltoTotalBase(
          total: total,
          totalPagadoBase: pagado,
          falta: false,
        ),
        500,
      );
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

    test('acepta transferencia sin destino si la tienda no tiene ninguno', () {
      final pagos = {'CUP': const PagoMonedaState(transfer: 960)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);
      expect(
        PaymentLogic.canConfirm(
          total: 960,
          falta: false,
          totalPagadoBase: pagado,
          pagosLinea: lineas(pagos, 'CUP'),
          hasPagos: true,
          hasTransferDestinations: false,
        ),
        isTrue,
      );
    });

    test('rechaza la venta si la cuenta se quedó sin productos', () {
      // Vaciar el carrito desde la pantalla de cobro deja el total en 0 con el
      // pago ya sembrado: sin hasItems eso habilitaba una venta de 0 sin
      // productos.
      final pagos = {'CUP': const PagoMonedaState(cash: 1000)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);
      expect(
        PaymentLogic.canConfirm(
          total: 0,
          falta: false,
          totalPagadoBase: pagado,
          pagosLinea: lineas(pagos, 'CUP'),
          hasPagos: true,
          hasItems: false,
        ),
        isFalse,
      );
    });

    test('sin productos no se puede vender ni con el pago cubierto', () {
      final pagos = {'CUP': const PagoMonedaState(cash: 1000)};
      final pagado = PaymentLogic.totalPagadoBase(pagos, 'CUP', tasas);
      expect(
        PaymentLogic.canConfirm(
          total: 1000,
          falta: false,
          totalPagadoBase: pagado,
          pagosLinea: lineas(pagos, 'CUP'),
          hasPagos: true,
          hasItems: false,
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

    test('cobro en USD no entrega más vuelto del debido (redondea hacia abajo)',
        () {
      // Debido: 200 CUP. En USD (tasa 400) son 0.5 USD; con la denominación
      // mínima de 1 USD, un redondeo hacia arriba entregaría 1 USD = 400 CUP,
      // el doble de lo debido. El vuelto total nunca debe superar lo debido por
      // una denominación completa de la moneda de cobro.
      const total = 800.0;
      final pagos = [
        PagoLinea(
          tipo: 'cash',
          moneda: 'USD',
          monto: 2.5, // = 1000 CUP
          equivalenteBase: 1000,
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

      final totalVueltoBase = vuelto.fold<double>(
        0,
        (s, v) =>
            s + CurrencyUtils.convertToBase(v.monto, v.moneda, tasas, 'CUP'),
      );
      // Debe cubrir lo debido...
      expect(totalVueltoBase, greaterThanOrEqualTo(200));
      // ...pero sin entregar un billete entero de USD (400 CUP) de más.
      expect(totalVueltoBase, lessThan(400));
      // No debe haber una línea de vuelto en USD por 0.5 redondeado a 1.
      expect(vuelto.where((v) => v.moneda == 'USD'), isEmpty);
    });

    test(
        'cobro y vuelto en la misma moneda no redondean el vuelto hacia arriba',
        () {
      // Total 10.34 USD, paga 11 USD: el vuelto exacto es 0.66. Con
      // denominación mínima de 1 USD, redondear hacia arriba entregaría 1
      // USD, regalando 0.34 al cliente a costa de la caja.
      const total = 10.34;
      final pagos = [
        PagoLinea(
          tipo: 'cash',
          moneda: 'USD',
          monto: 11,
          equivalenteBase: 11,
        ),
      ];

      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: total,
        pagos: pagos,
        monedaCobro: 'USD',
        monedaBase: 'USD',
        tasas: tasas,
        denominaciones: {'USD': [100, 50, 20, 10, 5, 1]},
      );

      expect(vuelto, isEmpty);
    });

    test('vuelto exacto en moneda única sigue devolviendo el entero completo',
        () {
      const total = 800.0;
      final pagos = [
        PagoLinea(
          tipo: 'cash',
          moneda: 'CUP',
          monto: 1200,
          equivalenteBase: 1200,
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
      expect(vuelto.single.monto, 400);
    });
  });

  group('PaymentLogic.montosRapidos', () {
    // Denominaciones de USD tal como las siembra el backend.
    const usdDenoms = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0];

    test('ofrece el siguiente billete sobre el exacto', () {
      // Total 821,48 -> exacto 822. 820+5, 820+10, 820+20.
      expect(
        PaymentLogic.montosRapidos(exacto: 822, denominaciones: usdDenoms),
        [825, 830, 840],
      );
    });

    test('nunca repite el propio exacto', () {
      // La denominación de 1 daría 822, que ya es el botón "Exacto".
      final montos =
          PaymentLogic.montosRapidos(exacto: 822, denominaciones: usdDenoms);

      expect(montos, isNot(contains(822)));
      expect(montos.every((m) => m > 822), isTrue);
    });

    test('con un exacto ya redondo salta al siguiente múltiplo', () {
      // 800 es múltiplo de 1, 5, 10, 20, 50 y 100: todos darían 800.
      final montos =
          PaymentLogic.montosRapidos(exacto: 800, denominaciones: usdDenoms);

      expect(montos, isEmpty);
    });

    test('deduplica los múltiplos que coinciden', () {
      // 10 y 20 sobre 815 dan ambos 820; solo se ofrece una vez.
      expect(
        PaymentLogic.montosRapidos(
          exacto: 815,
          denominaciones: [10, 20, 50],
        ),
        [820, 850],
      );
    });

    test('ordena las denominaciones aunque lleguen desordenadas', () {
      // MonedaInfoModel las ordena por el campo `orden`, no por valor.
      expect(
        PaymentLogic.montosRapidos(
          exacto: 822,
          denominaciones: [100, 5, 50, 10, 20, 1],
        ),
        [825, 830, 840],
      );
    });

    test('respeta el límite de cantidad', () {
      expect(
        PaymentLogic.montosRapidos(
          exacto: 822,
          denominaciones: usdDenoms,
          cantidad: 2,
        ),
        [825, 830],
      );
    });

    test('sin denominaciones no ofrece nada', () {
      expect(
        PaymentLogic.montosRapidos(exacto: 822, denominaciones: const []),
        isEmpty,
      );
    });

    test('con exacto en cero no ofrece nada', () {
      expect(
        PaymentLogic.montosRapidos(exacto: 0, denominaciones: usdDenoms),
        isEmpty,
      );
    });
  });

  group('PaymentLogic.defaultDestId', () {
    TransferDestinationModel dest(String id, {bool isDefault = false}) =>
        TransferDestinationModel(id: id, nombre: id, isDefault: isDefault);

    test('sin destinos devuelve cadena vacía', () {
      expect(PaymentLogic.defaultDestId(const []), '');
    });

    test('con uno solo devuelve ese, aunque no esté marcado', () {
      expect(PaymentLogic.defaultDestId([dest('d1')]), 'd1');
    });

    test('con varios devuelve el marcado por defecto', () {
      expect(
        PaymentLogic.defaultDestId([dest('d1'), dest('d2', isDefault: true)]),
        'd2',
      );
    });

    test('con varios y ninguno marcado devuelve el primero', () {
      expect(PaymentLogic.defaultDestId([dest('d1'), dest('d2')]), 'd1');
    });
  });

  group('vuelto sin fracciones ni de más', () {
    const usdDenoms = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0];
    const eurDenoms = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0];

    test('nunca entrega más vuelto del debido', () {
      // Con la regla vieja el resto en moneda base se redondeaba hacia ARRIBA:
      // 200,5 CUP se convertían en 201 y la venta entregaba de más.
      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: 999.5,
        pagos: [
          PagoLinea(
            tipo: 'cash',
            moneda: 'USD',
            monto: 5,
            equivalenteBase: 2000,
          ),
        ],
        monedaCobro: 'USD',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {'CUP': cupDenoms, 'USD': usdDenoms},
      );

      final cup = vuelto.firstWhere((v) => v.moneda == 'CUP');
      expect(cup.monto, 200);

      final entregadoBase = vuelto.fold<double>(
        0,
        (s, v) => s + CurrencyUtils.convertToBase(v.monto, v.moneda, tasas, 'CUP'),
      );
      expect(entregadoBase, lessThanOrEqualTo(1000.5));
    });

    test('ninguna línea del vuelto lleva decimales', () {
      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: 999.5,
        pagos: [
          PagoLinea(
            tipo: 'cash',
            moneda: 'USD',
            monto: 5,
            equivalenteBase: 2000,
          ),
        ],
        monedaCobro: 'USD',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {'CUP': cupDenoms, 'USD': usdDenoms},
      );

      for (final linea in vuelto) {
        expect(linea.monto, linea.monto.roundToDouble(),
            reason: '${linea.monto} ${linea.moneda} tiene fracción');
      }
    });

    test('el resto se entrega en la moneda más fina, no en la base', () {
      // El caso del diseño: base USD, el cliente paga en EUR y el vuelto sale
      // en CUP, que es la única moneda con la que se puede afinar tan poco.
      final vuelto = PaymentLogic.calcularVueltoAuto(
        // 1 EUR = 440 CUP y 1 USD = 400 CUP, así que 0,01 EUR son 4,4 CUP.
        totalBase: 137.97 * 440 / 400,
        pagos: [
          PagoLinea(
            tipo: 'cash',
            moneda: 'EUR',
            monto: 137.98,
            equivalenteBase: 137.98 * 440 / 400,
          ),
        ],
        monedaCobro: 'EUR',
        monedaBase: 'USD',
        tasas: tasas,
        denominaciones: {'CUP': cupDenoms, 'USD': usdDenoms, 'EUR': eurDenoms},
        monedasVuelto: const ['EUR', 'USD', 'CUP'],
      );

      expect(vuelto.map((v) => v.moneda), ['CUP']);
      expect(vuelto.single.monto, 4);
    });

    test('trunca a la denominación mínima: 145,99 CUP se pagan como 145', () {
      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: 1000,
        pagos: [
          PagoLinea(
            tipo: 'cash',
            moneda: 'CUP',
            monto: 1145.99,
            equivalenteBase: 1145.99,
          ),
        ],
        monedaCobro: 'CUP',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {'CUP': cupDenoms},
      );

      expect(vuelto.single.monto, 145);
    });

    test('solo reparte entre las monedas que la tienda puede entregar', () {
      // CUP sería la más fina, pero si no está habilitada el resto se queda sin
      // entregar en vez de inventar una moneda que la caja no tiene.
      final vuelto = PaymentLogic.calcularVueltoAuto(
        totalBase: 999.5,
        pagos: [
          PagoLinea(
            tipo: 'cash',
            moneda: 'USD',
            monto: 5,
            equivalenteBase: 2000,
          ),
        ],
        monedaCobro: 'USD',
        monedaBase: 'CUP',
        tasas: tasas,
        denominaciones: {'CUP': cupDenoms, 'USD': usdDenoms},
        monedasVuelto: const ['USD'],
      );

      expect(vuelto.map((v) => v.moneda), ['USD']);
      expect(vuelto.single.monto, 2);
    });
  });

  group('CurrencyUtils.monedaMasFina', () {
    test('elige la moneda cuya denominación mínima vale menos', () {
      expect(
        CurrencyUtils.monedaMasFina(
          monedas: const ['USD', 'EUR', 'CUP'],
          denominaciones: {
            'CUP': cupDenoms,
            'USD': const [1.0, 100.0],
            'EUR': const [1.0, 100.0],
          },
          tasas: tasas,
          monedaBase: 'USD',
        ),
        'CUP',
      );
    });

    test('con una sola moneda devuelve esa', () {
      expect(
        CurrencyUtils.monedaMasFina(
          monedas: const ['USD'],
          denominaciones: {'USD': const [1.0]},
          tasas: tasas,
          monedaBase: 'USD',
        ),
        'USD',
      );
    });

    test('sin denominaciones compara por el valor de la unidad', () {
      // Sin datos del servidor la denominación mínima es 1, así que gana la
      // moneda que menos vale: CUP.
      expect(
        CurrencyUtils.monedaMasFina(
          monedas: const ['USD', 'CUP'],
          denominaciones: const {},
          tasas: tasas,
          monedaBase: 'USD',
        ),
        'CUP',
      );
    });
  });

  group('PaymentLogic.desglosarEnBilletes', () {
    const usdDenoms = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0];

    test('desglosa de mayor a menor', () {
      expect(
        PaymentLogic.desglosarEnBilletes(224, usdDenoms),
        {100.0: 2, 20.0: 1, 1.0: 4},
      );
    });

    test('no incluye denominaciones que no se usan', () {
      expect(PaymentLogic.desglosarEnBilletes(100, usdDenoms), {100.0: 1});
    });

    test('devuelve null si el monto tiene fracción', () {
      expect(PaymentLogic.desglosarEnBilletes(224.5, usdDenoms), isNull);
    });

    test('devuelve null si las denominaciones no cubren el monto', () {
      expect(PaymentLogic.desglosarEnBilletes(7, const [5, 10]), isNull);
    });

    test('monto cero da un desglose vacío', () {
      expect(PaymentLogic.desglosarEnBilletes(0, usdDenoms), isEmpty);
    });

    test('acepta denominaciones desordenadas', () {
      expect(
        PaymentLogic.desglosarEnBilletes(224, const [1, 100, 20, 5, 50, 10]),
        {100.0: 2, 20.0: 1, 1.0: 4},
      );
    });
  });

  group('CurrencyUtils.variantesDeVuelto', () {
    // El escenario de los mockups: 1 USD = 675 CUP, base USD.
    const tasasMockup = {'USD': 675.0, 'CUP': 1.0};
    const denomsMockup = {
      'USD': [1.0, 5.0, 10.0, 20.0, 50.0, 100.0],
      'CUP': cupDenoms,
    };
    const elegibles = ['USD', 'CUP'];

    List<Map<String, double>> variantes(double debido) =>
        CurrencyUtils.variantesDeVuelto(
          vueltoTotalBase: debido,
          monedaCobro: 'USD',
          monedaBase: 'USD',
          tasas: tasasMockup,
          denominaciones: denomsMockup,
          monedasVuelto: elegibles,
        );

    test('con 3,52 USD a dar ofrece dos repartos', () {
      // Pagar 25 USD sobre 21,48: 3 USD + 351 CUP, o todo en CUP.
      expect(variantes(3.52), [
        {'USD': 3.0, 'CUP': 351.0},
        {'CUP': 2376.0},
      ]);
    });

    test('con 8,52 USD a dar ofrece tres repartos', () {
      // Pagar 30 USD sobre 21,48, el caso de la imagen.
      expect(variantes(8.52), [
        {'USD': 8.0, 'CUP': 351.0},
        {'USD': 5.0, 'CUP': 2376.0},
        {'CUP': 5751.0},
      ]);
    });

    test('la primera variante es la que devuelve calcularVuelto', () {
      final auto = CurrencyUtils.calcularVuelto(
        totalBase: 21.48,
        pagos: [
          PagoLinea(
            tipo: 'cash',
            moneda: 'USD',
            monto: 30,
            equivalenteBase: 30,
          ),
        ],
        monedaCobro: 'USD',
        monedaBase: 'USD',
        tasas: tasasMockup,
        denominaciones: denomsMockup,
        monedasVuelto: elegibles,
      );

      expect(
        {for (final l in auto) l.moneda: l.monto},
        variantes(8.52).first,
      );
    });

    test('pagar en la moneda más fina da una sola variante', () {
      expect(
        CurrencyUtils.variantesDeVuelto(
          vueltoTotalBase: 8.52,
          monedaCobro: 'CUP',
          monedaBase: 'USD',
          tasas: tasasMockup,
          denominaciones: denomsMockup,
          monedasVuelto: elegibles,
        ),
        [
          {'CUP': 5751.0},
        ],
      );
    });

    test('ninguna variante entrega de más ni con fracciones', () {
      for (final reparto in variantes(8.52)) {
        var entregado = 0.0;
        for (final e in reparto.entries) {
          expect(e.value, e.value.roundToDouble(),
              reason: '${e.value} ${e.key} tiene fracción');
          entregado += CurrencyUtils.convertToBase(
            e.value,
            e.key,
            tasasMockup,
            'USD',
          );
        }
        expect(entregado, lessThanOrEqualTo(8.52 + 1e-9));
      }
    });

    test('respeta el tope y descarta duplicados', () {
      final limitadas = CurrencyUtils.variantesDeVuelto(
        vueltoTotalBase: 8.52,
        monedaCobro: 'USD',
        monedaBase: 'USD',
        tasas: tasasMockup,
        denominaciones: denomsMockup,
        monedasVuelto: elegibles,
        max: 2,
      );

      expect(limitadas, hasLength(2));
      // Las denominaciones de 10 en adelante darían todas el mismo reparto.
      expect(variantes(8.52), hasLength(3));
    });

    test('sin vuelto pendiente no hay variantes', () {
      expect(variantes(0), isEmpty);
    });
  });
}
