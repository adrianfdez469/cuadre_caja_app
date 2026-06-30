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
      expect(find.text('Agregar transferencia'), findsOneWidget);

      await tester.tap(find.text('Agregar transferencia'));
      await tester.pumpAndSettle();

      expect(transferField, findsOneWidget);
      expect(find.text('Ocultar transferencia'), findsOneWidget);
    });

    testWidgets('inicializa efectivo con el total a cobrar', (tester) async {
      await pumpPaymentModal(tester, total: 1500);

      expect(find.text('1500.00'), findsWidgets);
    });

    testWidgets('al agregar transferencia ajusta efectivo en modo mixto',
        (tester) async {
      await pumpPaymentModal(tester, total: 1000);

      await tester.tap(find.text('Agregar transferencia'));
      await tester.pumpAndSettle();

      await tester.enterText(transferField, '300');
      await tester.pumpAndSettle();

      final cashController =
          tester.widget<TextField>(cashField).controller!;
      expect(cashController.text, '700.00');
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

    testWidgets('funciona con moneda base USD', (tester) async {
      await pumpPaymentModal(
        tester,
        total: 10,
        monedaBase: 'USD',
        tasas: const {'USD': 400, 'CUP': 1},
      );

      expect(find.text('10.00'), findsWidgets);
      expect(find.text('Confirmar Venta'), findsOneWidget);
    });
  });
}
