import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  group('CobrarScreen — estado inicial', () {
    testWidgets('siembra el efectivo con el total a cobrar', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      expect(montoDe(tester, cashFieldDe('CUP')), '1500');
    });

    testWidgets('la cabecera nombra la cuenta y cuenta los productos',
        (tester) async {
      await pumpCobrarScreen(tester);

      expect(find.text('Cobrar'), findsOneWidget);
      expect(find.text('Cuenta #1 · 1 producto'), findsOneWidget);
    });

    testWidgets('con el total cubierto no muestra falta ni cambio',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      expect(find.text('FALTA POR CUBRIR'), findsNothing);
      expect(find.text('CAMBIO'), findsNothing);
    });
  });

  group('CobrarScreen — transferencia', () {
    testWidgets('el campo está oculto hasta activar el ícono', (tester) async {
      await pumpCobrarScreen(tester);

      expect(transferFieldDe('CUP'), findsNothing);

      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();

      expect(transferFieldDe('CUP'), findsOneWidget);
    });

    testWidgets('lo que entra por transferencia sale del efectivo',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, transferFieldDe('CUP'), '500');

      expect(montoDe(tester, transferFieldDe('CUP')), '500');
      expect(montoDe(tester, cashFieldDe('CUP')), '1000');
    });

    testWidgets('editar el efectivo no toca la transferencia', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, transferFieldDe('CUP'), '500');
      await escribirMonto(tester, cashFieldDe('CUP'), '1200');

      expect(montoDe(tester, transferFieldDe('CUP')), '500');
      expect(montoDe(tester, cashFieldDe('CUP')), '1200');
    });

    testWidgets('desactivar el ícono devuelve el importe al efectivo',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, transferFieldDe('CUP'), '500');
      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();

      expect(transferFieldDe('CUP'), findsNothing);
      expect(montoDe(tester, cashFieldDe('CUP')), '1500');
    });

    testWidgets('con importe aparece el destino, ya preseleccionado',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('destino-CUP')), findsNothing);

      await escribirMonto(tester, transferFieldDe('CUP'), '500');

      expect(find.byKey(const Key('destino-CUP')), findsOneWidget);
      expect(find.text('Banco'), findsOneWidget);
    });

    testWidgets('sin destinos configurados avisa y deja vender',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500, destinations: const []);

      await tester.tap(transferToggleDe('CUP'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, transferFieldDe('CUP'), '500');

      expect(find.textContaining('Sin destinos de transferencia'), findsOneWidget);
      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Vender'),
      );
      expect(boton.onPressed, isNotNull);
    });
  });

  group('CobrarScreen — falta y cambio', () {
    testWidgets('pagar de menos muestra la falta y bloquea Vender',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await escribirMonto(tester, cashFieldDe('CUP'), '1000');

      expect(find.text('FALTA POR CUBRIR'), findsOneWidget);
      expect(find.text('500.00 CUP'), findsOneWidget);
      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Vender'),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('pagar de más muestra el cambio', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await escribirMonto(tester, cashFieldDe('CUP'), '2000');

      expect(find.text('CAMBIO'), findsOneWidget);
      expect(find.text('500.00 CUP'), findsOneWidget);
    });

    testWidgets('el cambio abre la hoja de reparto', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);
      await escribirMonto(tester, cashFieldDe('CUP'), '2000');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();

      expect(find.text('Cómo dar el cambio'), findsOneWidget);
      expect(find.text('Otro reparto'), findsOneWidget);
    });
  });

  /// El "Resto" de la hoja de reparto, por Key: el mismo importe puede estar
  /// también en la tarjeta de atrás.
  String restoDelCambio(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('cambio-resto'))).data ?? '';

  group('CobrarScreen — reparto del cambio', () {
    /// Escenario de los mockups: base USD, 1 USD = 675 CUP, total 21,48.
    Future<void> pumpMockup(WidgetTester tester, String paga) async {
      await pumpCobrarScreen(
        tester,
        total: 21.48,
        monedaBase: 'USD',
        tasas: const {'USD': 675, 'CUP': 1},
        monedasAlternativas: const ['CUP'],
      );
      await escribirMonto(tester, cashFieldDe('USD'), paga);
    }

    testWidgets('la tarjeta muestra todas las monedas del cambio',
        (tester) async {
      await pumpMockup(tester, '30');

      // Antes la segunda quedaba recortada por el ellipsis de una sola línea.
      expect(find.text('8.00 USD'), findsOneWidget);
      expect(find.text('351.00 CUP'), findsOneWidget);
    });

    testWidgets('ofrece las variantes de reparto del diseño', (tester) async {
      await pumpMockup(tester, '30');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();

      expect(find.text('8.00 USD + 351.00 CUP'), findsOneWidget);
      expect(find.text('5.00 USD + 2376.00 CUP'), findsOneWidget);
      expect(find.text('5751.00 CUP'), findsOneWidget);
      expect(find.text('Otro reparto'), findsOneWidget);
    });

    testWidgets('con menos vuelto ofrece menos variantes', (tester) async {
      await pumpMockup(tester, '25');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();

      expect(find.text('3.00 USD + 351.00 CUP'), findsOneWidget);
      expect(find.text('2376.00 CUP'), findsOneWidget);
      expect(find.text('5751.00 CUP'), findsNothing);
    });

    testWidgets('elegir otra variante la aplica a la tarjeta', (tester) async {
      await pumpMockup(tester, '30');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5751.00 CUP'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Listo'));
      await tester.pumpAndSettle();

      expect(find.text('5751.00 CUP'), findsOneWidget);
      expect(find.text('8.00 USD'), findsNothing);
    });

    testWidgets('"Otro reparto" no lista la moneda más fina', (tester) async {
      await pumpMockup(tester, '30');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro reparto'));
      await tester.pumpAndSettle();

      // CUP recibe el resto, así que no se reparte a mano.
      expect(find.byKey(const Key('reparto-USD')), findsOneWidget);
      expect(find.byKey(const Key('reparto-CUP')), findsNothing);
      expect(find.text('Resto'), findsOneWidget);
      expect(restoDelCambio(tester), '5751.00 CUP');
    });

    testWidgets('cambiar lo que paga el cliente descarta el reparto manual',
        (tester) async {
      await pumpMockup(tester, '30');

      // El cajero arma el reparto a mano: 5 USD y el resto en CUP.
      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro reparto'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, find.byKey(const Key('reparto-USD')), '5');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Listo'));
      await tester.pumpAndSettle();
      expect(find.text('5.00 USD'), findsOneWidget);

      // Y después el cliente paga otra cosa. Ese reparto se armó para 8,52 USD
      // de vuelto: dejarlo entregaría 5 USD sobre los 3,52 que ahora se deben.
      await escribirMonto(tester, cashFieldDe('USD'), '25');

      expect(find.text('5.00 USD'), findsNothing);
      expect(find.text('3.00 USD'), findsOneWidget);
      expect(find.text('351.00 CUP'), findsOneWidget);
    });

    testWidgets('escribir un monto baja el resto', (tester) async {
      await pumpMockup(tester, '30');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro reparto'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, find.byKey(const Key('reparto-USD')), '5');

      // 5 USD son 3375 CUP: quedan 2376 de los 5751.
      expect(restoDelCambio(tester), '2376.00 CUP');
    });

    testWidgets('no se puede repartir más de lo debido', (tester) async {
      await pumpMockup(tester, '30');

      await tester.tap(find.text('CAMBIO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro reparto'));
      await tester.pumpAndSettle();
      await escribirMonto(tester, find.byKey(const Key('reparto-USD')), '99');

      // Se recorta a los 8 USD que caben en los 8,52 debidos; los 0,52 que
      // sobran se van al resto, que nunca queda en negativo.
      expect(find.text('8'), findsOneWidget);
      expect(restoDelCambio(tester), '351.00 CUP');
      expect(find.text('99'), findsNothing);
    });
  });

  group('CobrarScreen — montos rápidos', () {
    testWidgets('"Exacto" cubre el total', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await escribirMonto(tester, cashFieldDe('CUP'), '1000');
      expect(find.text('FALTA POR CUBRIR'), findsOneWidget);

      await tester.tap(find.text('Exacto'));
      await tester.pumpAndSettle();

      expect(montoDe(tester, cashFieldDe('CUP')), '1500');
      expect(find.text('FALTA POR CUBRIR'), findsNothing);
    });

    testWidgets('ofrece los siguientes billetes sobre el exacto',
        (tester) async {
      // Total 1490 con denominaciones CUP [1,3,5,10,20,50,100,200,500,1000]:
      // 1490 ya es múltiplo de 5 y 10, así que el primer salto es el de 3.
      await pumpCobrarScreen(tester, total: 1490);

      expect(find.text('Exacto'), findsOneWidget);
      expect(find.text('1491'), findsOneWidget);
      expect(find.text('1500'), findsOneWidget);
    });
  });

  group('CobrarScreen — varias monedas', () {
    testWidgets('agregar una segunda moneda muestra los botones de quitar',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      expect(find.byKey(const Key('quitar-CUP')), findsNothing);

      await tester.tap(find.text('Agregar forma de pago'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Efectivo USD'));
      await tester.pumpAndSettle();

      expect(cashFieldDe('USD'), findsOneWidget);
      expect(find.byKey(const Key('quitar-CUP')), findsOneWidget);
      expect(find.byKey(const Key('quitar-USD')), findsOneWidget);
    });

    testWidgets('la hoja muestra el importe de cada moneda, no cero',
        (tester) async {
      // Con el efectivo sembrado en el total, no falta nada; aun así la hoja
      // debe decir cuánto sería en cada moneda. Antes salía todo en 0,00.
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(find.text('Agregar forma de pago'));
      await tester.pumpAndSettle();

      // 1500 CUP a 400 CUP/USD son 3,75 USD.
      expect(find.text('3.75 USD'), findsOneWidget);
      expect(find.text('0.00 USD'), findsNothing);
      expect(find.text('Ya está cubierto el total'), findsOneWidget);
    });

    testWidgets('si falta por cubrir, la hoja muestra lo que falta',
        (tester) async {
      await pumpCobrarScreen(tester, total: 1500);
      await escribirMonto(tester, cashFieldDe('CUP'), '700');

      await tester.tap(find.text('Agregar forma de pago'));
      await tester.pumpAndSettle();

      // Faltan 800 CUP = 2 USD.
      expect(find.text('2.00 USD'), findsOneWidget);
      expect(find.text('Ya está cubierto el total'), findsNothing);
    });

    testWidgets('quitar deja siempre al menos un bloque', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(find.text('Agregar forma de pago'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Efectivo USD'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quitar-USD')));
      await tester.pumpAndSettle();

      expect(cashFieldDe('USD'), findsNothing);
      expect(cashFieldDe('CUP'), findsOneWidget);
      expect(find.byKey(const Key('quitar-CUP')), findsNothing);
    });

    testWidgets('la píldora cambia la moneda del bloque', (tester) async {
      await pumpCobrarScreen(tester, total: 1500);

      await tester.tap(find.text('CUP').first);
      await tester.pumpAndSettle();
      expect(find.text('Moneda del pago'), findsOneWidget);

      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();

      expect(cashFieldDe('CUP'), findsNothing);
      // 1500 CUP a 400 CUP/USD son 3.75 -> se redondea al alza a 4.
      expect(montoDe(tester, cashFieldDe('USD')), '4');
    });
  });

  group('CobrarScreen — moneda base USD', () {
    testWidgets('siembra y cobra en la moneda base del negocio',
        (tester) async {
      await pumpCobrarScreen(tester, total: 100, monedaBase: 'USD');

      expect(montoDe(tester, cashFieldDe('USD')), '100');
      expect(find.text('FALTA POR CUBRIR'), findsNothing);
    });

    testWidgets('sin la tasa de USD no ofrece cobrar en otra moneda',
        (tester) async {
      // Las tasas se anclan en CUP: sin la de USD, cobrar 1360 CUP en un
      // negocio con base USD registraría 1360 USD. Se ofrece solo la base, que
      // no necesita conversión, y se dice por qué.
      await pumpCobrarScreen(
        tester,
        total: 100,
        monedaBase: 'USD',
        tasas: const {'EUR': 775},
        monedasAlternativas: const ['EUR'],
      );

      expect(find.text('Agregar forma de pago'), findsNothing);
      expect(
        find.textContaining('falta registrar la tasa de cambio de USD'),
        findsOneWidget,
      );
    });

    testWidgets('con la tasa de USD sí ofrece las demás monedas',
        (tester) async {
      await pumpCobrarScreen(
        tester,
        total: 100,
        monedaBase: 'USD',
        tasas: const {'USD': 680, 'EUR': 775},
        monedasAlternativas: const ['EUR'],
      );

      expect(find.text('Agregar forma de pago'), findsOneWidget);
      expect(
        find.textContaining('falta registrar la tasa de cambio'),
        findsNothing,
      );
    });
  });

  group('CobrarScreen — venta registrada', () {
    testWidgets('vender en efectivo exacto lleva a la pantalla de éxito',
        (tester) async {
      final config = buildTestConfig();
      final sync = FakeSyncService(
        destinations: [
          TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true),
        ],
        periodoAbierto: PeriodoModel(
          id: 'periodo-1',
          tiendaId: 't1',
          fechaInicio: DateTime(2026, 1, 1),
          estaAbierto: true,
        ),
      );
      final cart = CartModel(
        id: 'c1',
        nombre: 'Cuenta #1',
        items: [
          CartItemModel(
            productoTiendaId: 'p1',
            nombre: 'Producto',
            precio: 1000,
            monedaPrecioCode: 'CUP',
          ),
        ],
      );

      await pumpCobrarScreenFull(
        tester,
        config: config,
        cart: cart,
        syncService: sync,
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Vender'));
      await tester.pumpAndSettle();

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.text('Nueva venta'), findsOneWidget);
      // El harness arranca offline: se muestra la nota de sincronización.
      expect(find.textContaining('Sin conexión'), findsOneWidget);
    });

    testWidgets('la pantalla de éxito resume quién cobró y cómo',
        (tester) async {
      final config = buildTestConfig();
      final sync = FakeSyncService(
        destinations: [
          TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true),
        ],
        periodoAbierto: PeriodoModel(
          id: 'periodo-1',
          tiendaId: 't1',
          fechaInicio: DateTime(2026, 1, 1),
          estaAbierto: true,
        ),
      );
      final cart = CartModel(
        id: 'c1',
        nombre: 'Cuenta #1',
        items: [
          CartItemModel(
            productoTiendaId: 'p1',
            nombre: 'Producto',
            precio: 1000,
            monedaPrecioCode: 'CUP',
          ),
        ],
      );

      await pumpCobrarScreenFull(
        tester,
        config: config,
        cart: cart,
        syncService: sync,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Vender'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Test'), findsOneWidget);
      expect(find.text('Cobrado 1000.00 CUP'), findsOneWidget);
      expect(
        find.textContaining('Efectivo CUP · recibido 1000.00 de 1000.00'),
        findsOneWidget,
      );
      // Imprimir queda para otra tanda.
      expect(find.text('Imprimir'), findsNothing);
    });
  });
}
