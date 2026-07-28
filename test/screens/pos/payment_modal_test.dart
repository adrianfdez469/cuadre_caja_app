import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/payment_test_harness.dart';

void main() {
  group('PaymentModal UI', () {
    testWidgets('no muestra selector Efectivo/Transferencia/Mixto', (tester) async {
      await pumpPaymentModal(tester);

      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('Transfer.'), findsNothing);
      expect(find.text('Mixto'), findsNothing);
      expect(find.byType(SegmentedButton<String>), findsNothing);
    });

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
