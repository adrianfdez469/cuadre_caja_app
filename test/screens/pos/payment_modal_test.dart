import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  group('PaymentModal UI — paso "elegir forma de pago"', () {
    testWidgets('muestra tarjetas dinámicas por moneda y el CTA se habilita al elegir',
        (tester) async {
      final config = buildTestConfig();
      final sync = FakeSyncService(
        destinations: [TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true)],
      );
      final cart = CartModel(
        id: 'c1',
        nombre: 'Cuenta #1',
        items: [
          CartItemModel(
            productoTiendaId: 'p1',
            nombre: 'Producto',
            precio: 1500,
            monedaPrecioCode: 'CUP',
          ),
        ],
      );

      await tester.pumpWidget(
        buildPaymentModalHarness(config: config, cart: cart, syncService: sync),
      );
      await tester.pumpAndSettle();

      // Una tarjeta "Efectivo <moneda>" por cada moneda que admite efectivo,
      // una "Transferencia <moneda>" por cada moneda que admite transferencia
      // (MLC no, según buildTestConfig), y siempre "Pago mixto".
      expect(find.text('Efectivo CUP'), findsOneWidget);
      expect(find.text('Efectivo USD'), findsOneWidget);
      expect(find.text('Efectivo MLC'), findsOneWidget);
      expect(find.text('Transferencia CUP'), findsOneWidget);
      expect(find.text('Transferencia USD'), findsOneWidget);
      expect(find.text('Transferencia MLC'), findsNothing);
      expect(find.text('Pago mixto'), findsOneWidget);

      final ctaAntes = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
      );
      expect(ctaAntes.onPressed, isNull);

      await tester.tap(find.text('Efectivo CUP'));
      await tester.pumpAndSettle();

      final ctaDespues = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
      );
      expect(ctaDespues.onPressed, isNotNull);
    });

    testWidgets(
        'el efectivo se redondea por exceso a un entero; la transferencia usa el monto exacto',
        (tester) async {
      final config = buildTestConfig();
      final sync = FakeSyncService(
        destinations: [TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true)],
      );
      // Total: 999,50 CUP ≈ 2,49875 USD (tasa 400). El efectivo en USD debe
      // subir al entero superior (3); la transferencia en USD debe quedar en
      // el monto exacto de la conversión (2.50), sin redondear.
      final cart = CartModel(
        id: 'c1',
        nombre: 'Cuenta #1',
        items: [
          CartItemModel(
            productoTiendaId: 'p1',
            nombre: 'Producto',
            precio: 999.5,
            monedaPrecioCode: 'CUP',
          ),
        ],
      );

      await tester.pumpWidget(
        buildPaymentModalHarness(config: config, cart: cart, syncService: sync),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 USD'), findsOneWidget);
      expect(find.text('2.50 USD'), findsOneWidget);
    });
  });

  group('PaymentModal UI — paso "efectivo y vuelto"', () {
    testWidgets('el atajo "Exacto" precarga el sugerido y el teclado edita el monto',
        (tester) async {
      final config = buildTestConfig();
      final sync = FakeSyncService(
        destinations: [TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true)],
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

      await tester.pumpWidget(
        buildPaymentModalHarness(config: config, cart: cart, syncService: sync),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Efectivo CUP'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar cobro'));
      await tester.pumpAndSettle();

      // El panel de falta/cambio queda debajo del teclado numérico: los
      // finders por defecto ignoran contenido "offstage" (fuera del scroll
      // visible), así que hay que desplazarlo a la vista primero.
      await tester.ensureVisible(find.text('Cambio:', skipOffstage: false));
      await tester.pumpAndSettle();

      // Ya en el paso "Efectivo CUP": el sugerido cubre el total exacto.
      expect(find.text('Cambio:'), findsOneWidget);
      expect(find.text('Falta:'), findsNothing);

      // Tocar dígitos del teclado propio edita el monto tecleado.
      await tester.ensureVisible(find.text('5', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5', skipOffstage: false));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Falta:', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.text('Falta:'), findsOneWidget);

      // "Exacto" vuelve a cubrir el total.
      await tester.ensureVisible(find.text('Exacto', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exacto', skipOffstage: false));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Cambio:', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.text('Cambio:'), findsOneWidget);
      expect(find.text('Falta:'), findsNothing);
    });
  });

  group('PaymentModal UI — paso "cobro registrado"', () {
    testWidgets('confirmar una venta en efectivo exacto muestra la pantalla de éxito',
        (tester) async {
      final config = buildTestConfig();
      final sync = FakeSyncService(
        destinations: [TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true)],
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

      await pumpPaymentModalFull(tester, config: config, cart: cart, syncService: sync);

      await tester.tap(find.text('Efectivo CUP'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar cobro'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar Venta'));
      await tester.pumpAndSettle();

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.text('Nueva venta'), findsOneWidget);
      // Offline por defecto en el harness: se muestra la nota de sincronización.
      expect(find.textContaining('Sin conexión'), findsOneWidget);
    });
  });

  group('PaymentModal UI — paso "mixto" (multimoneda)', () {
    testWidgets('oculta transferencia hasta expandir', (tester) async {
      await pumpPaymentModal(tester);

      expect(transferField, findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Transferencia'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Transferencia'));
      await tester.pumpAndSettle();

      expect(transferField, findsOneWidget);
    });

    testWidgets('inicializa efectivo con el total a cobrar', (tester) async {
      await pumpPaymentModal(tester, total: 1500);

      expect(find.text('1500'), findsWidgets);
    });

    testWidgets('al escribir transferencia resta del efectivo', (tester) async {
      await pumpPaymentModal(tester, total: 1000);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Transferencia'));
      await tester.pumpAndSettle();

      await tester.enterText(transferField, '400');
      await tester.pumpAndSettle();

      final cashController =
          tester.widget<TextField>(cashField).controller!;
      expect(cashController.text, '600');
    });

    testWidgets('al modificar efectivo no cambia la transferencia',
        (tester) async {
      await pumpPaymentModal(tester, total: 1000);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Transferencia'));
      await tester.pumpAndSettle();

      await tester.enterText(transferField, '400');
      await tester.pumpAndSettle();

      await tester.enterText(cashField, '800');
      await tester.pumpAndSettle();

      final transferController =
          tester.widget<TextField>(transferField).controller!;
      expect(transferController.text, '400');
    });

    testWidgets('muestra cambio cuando el pago excede el total', (tester) async {
      await pumpPaymentModal(tester, total: 1000);

      await tester.enterText(cashField, '2000');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Cambio:', skipOffstage: false));
      await tester.pumpAndSettle();

      expect(find.text('Cambio:'), findsOneWidget);
      expect(find.textContaining('1000'), findsWidgets);
    });

    testWidgets('muestra falta cuando el pago es insuficiente', (tester) async {
      await pumpPaymentModal(tester, total: 1000);

      await tester.enterText(cashField, '500');
      await tester.pumpAndSettle();

      expect(find.text('Falta:'), findsOneWidget);
    });

    testWidgets('efectivo solo acepta enteros (sin decimales)', (tester) async {
      await pumpPaymentModal(tester, total: 1000);

      await tester.enterText(cashField, '1500.75');
      await tester.pumpAndSettle();

      final cashController =
          tester.widget<TextField>(cashField).controller!;
      expect(cashController.text, '1500');
    });

    testWidgets(
        'habilita confirmar con transferencia completa aunque la tienda no '
        'tenga destinos', (tester) async {
      await pumpPaymentModal(tester, total: 960, destinations: const []);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Transferencia'));
      await tester.pumpAndSettle();

      await tester.enterText(transferField, '960');
      await tester.pumpAndSettle();

      // El pago cubre el total: sin falta y sin cambio.
      expect(find.text('Falta:'), findsNothing);
      expect(find.text('Cambio:'), findsOneWidget);
      expect(
        find.textContaining('Sin destinos de transferencia configurados'),
        findsOneWidget,
      );

      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirmar Venta'),
      );
      expect(boton.onPressed, isNotNull);
    });

    testWidgets('exige destino de transferencia si la tienda tiene alguno',
        (tester) async {
      await pumpPaymentModal(tester, total: 960);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Transferencia'));
      await tester.pumpAndSettle();

      await tester.enterText(transferField, '960');
      await tester.pumpAndSettle();

      // Con destinos disponibles se preselecciona el default y se puede cobrar.
      expect(find.text('Destino de transferencia'), findsOneWidget);
      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirmar Venta'),
      );
      expect(boton.onPressed, isNotNull);
    });

    testWidgets('funciona con moneda base USD', (tester) async {
      await pumpPaymentModal(
        tester,
        total: 10,
        monedaBase: 'USD',
        tasas: const {'USD': 400, 'CUP': 1},
      );

      expect(find.text('10'), findsWidgets);
      expect(find.text('Confirmar Venta'), findsOneWidget);
    });
  });
}
