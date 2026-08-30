import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/monto_input_sheet.dart';

void main() {
  const denomsUsd = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0];

  /// Monta la hoja y devuelve el resultado con el que se cierra.
  Future<MontoInputResult?> pumpSheet(
    WidgetTester tester, {
    double montoInicial = 0,
    List<double> denominaciones = denomsUsd,
    Map<double, int> billetesIniciales = const {},
    bool permiteBilletes = true,
  }) async {
    MontoInputResult? resultado;
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultado = await MontoInputSheet.show(
                  context,
                  titulo: 'Efectivo USD',
                  moneda: 'USD',
                  montoInicial: montoInicial,
                  denominaciones: denominaciones,
                  billetesIniciales: billetesIniciales,
                  permiteBilletes: permiteBilletes,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultado;
  }

  Future<void> tocar(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(InkWell, label).last);
    await tester.pump();
  }

  Future<MontoInputResult?> listo(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Listo'));
    await tester.pumpAndSettle();
    return null;
  }

  group('modo Teclado', () {
    testWidgets('teclear dígitos arma el monto', (tester) async {
      await pumpSheet(tester);

      await tocar(tester, '8');
      await tocar(tester, '2');
      await tocar(tester, '0');

      expect(find.text('820'), findsOneWidget);
    });

    testWidgets('la tecla 000 agrega tres ceros', (tester) async {
      await pumpSheet(tester);

      await tocar(tester, '5');
      await tocar(tester, '000');

      expect(find.text('5000'), findsOneWidget);
    });

    testWidgets('el borrado quita el último dígito', (tester) async {
      await pumpSheet(tester, montoInicial: 822);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(find.text('82'), findsOneWidget);
    });

    testWidgets('sin denominaciones no ofrece la pestaña de billetes',
        (tester) async {
      await pumpSheet(tester, denominaciones: const []);

      expect(find.text('Billetes'), findsNothing);
      expect(find.text('Teclado'), findsNothing);
    });

    testWidgets('en transferencia no se cuentan billetes', (tester) async {
      await pumpSheet(tester, permiteBilletes: false);

      expect(find.text('Billetes'), findsNothing);
    });
  });

  group('monto que viene de la pantalla', () {
    testWidgets('la primera tecla lo reemplaza en vez de sumarse',
        (tester) async {
      await pumpSheet(tester, montoInicial: 224);
      expect(find.text('224'), findsOneWidget);

      await tocar(tester, '2');

      // Antes quedaba 2242: había que borrar cuatro veces para escribir otro
      // monto.
      expect(find.text('2'), findsWidgets);
      expect(find.text('224'), findsNothing);
    });

    testWidgets('la segunda tecla ya se suma con normalidad', (tester) async {
      await pumpSheet(tester, montoInicial: 224);

      await tocar(tester, '2');
      await tocar(tester, '2');
      await tocar(tester, '8');

      expect(find.text('228'), findsOneWidget);
    });

    testWidgets('borrar sigue quitando dígitos, no empieza de cero',
        (tester) async {
      await pumpSheet(tester, montoInicial: 224);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await tocar(tester, '8');

      expect(find.text('228'), findsOneWidget);
    });
  });

  group('preselección de billetes', () {
    testWidgets('al pasar a Billetes desglosa el monto escrito',
        (tester) async {
      await pumpSheet(tester, montoInicial: 224);

      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();

      expect(find.text('2×100'), findsOneWidget);
      expect(find.text('1×20'), findsOneWidget);
      expect(find.text('4×1'), findsOneWidget);
      expect(find.text('224'), findsOneWidget);
    });

    testWidgets('un monto que no se puede armar deja la pestaña en blanco',
        (tester) async {
      // 7 no se puede formar con billetes de 5 y 10.
      await pumpSheet(tester, montoInicial: 7, denominaciones: const [5, 10]);

      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('×'), findsNothing);
      // Y sobre todo: el monto no cambia por mirar los billetes.
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('el desglose preseleccionado se puede deshacer',
        (tester) async {
      await pumpSheet(tester, montoInicial: 224);
      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();

      // La pila arranca de mayor a menor, así que se deshace un billete de 1.
      await tester.tap(find.text('Deshacer'));
      await tester.pump();

      expect(find.text('223'), findsOneWidget);
      expect(find.text('3×1'), findsOneWidget);
    });
  });

  group('modo Billetes', () {
    Future<void> irABilletes(WidgetTester tester) async {
      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();
    }

    testWidgets('tocar billetes suma el monto y muestra el conteo',
        (tester) async {
      await pumpSheet(tester);
      await irABilletes(tester);

      for (var i = 0; i < 8; i++) {
        await tocar(tester, '100');
      }
      await tocar(tester, '20');

      expect(find.text('820'), findsOneWidget);
      expect(find.text('8×100'), findsOneWidget);
      expect(find.text('1×20'), findsOneWidget);
    });

    testWidgets('deshacer quita el último billete tocado', (tester) async {
      await pumpSheet(tester);
      await irABilletes(tester);

      await tocar(tester, '100');
      await tocar(tester, '20');
      expect(find.text('120'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pump();

      expect(find.text('100'), findsWidgets);
      expect(find.text('1×20'), findsNothing);
      expect(find.text('1×100'), findsOneWidget);
    });

    testWidgets('las denominaciones salen de mayor a menor', (tester) async {
      await pumpSheet(tester, denominaciones: [5, 100, 20]);
      await irABilletes(tester);

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == '100' || d == '20' || d == '5')
          .toList();

      expect(labels, ['100', '20', '5']);
    });

    testWidgets('devuelve el monto y el desglose al confirmar', (tester) async {
      MontoInputResult? res;
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  res = await MontoInputSheet.show(
                    context,
                    titulo: 'Efectivo USD',
                    moneda: 'USD',
                    montoInicial: 0,
                    denominaciones: denomsUsd,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();
      await tocar(tester, '50');
      await tocar(tester, '50');
      await listo(tester);

      expect(res!.monto, 100);
      expect(res!.billetes, {50.0: 2});
    });

    testWidgets('teclear después de contar billetes descarta el desglose',
        (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();
      await tocar(tester, '100');
      expect(find.text('1×100'), findsOneWidget);

      await tester.tap(find.text('Teclado'));
      await tester.pumpAndSettle();
      await tocar(tester, '7');

      await tester.tap(find.text('Billetes'));
      await tester.pumpAndSettle();
      expect(find.text('1×100'), findsNothing);
    });

    testWidgets('reabre en billetes cuando el monto se armó así',
        (tester) async {
      await pumpSheet(
        tester,
        montoInicial: 820,
        billetesIniciales: {100.0: 8, 20.0: 1},
      );

      expect(find.text('8×100'), findsOneWidget);
      expect(find.text('820'), findsOneWidget);
    });
  });
}
