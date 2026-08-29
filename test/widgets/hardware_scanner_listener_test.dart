import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/widgets/hardware_scanner_listener.dart';

/// La pistola es un teclado HID: escribe el código carácter a carácter y
/// termina con Enter.
Future<void> escanear(WidgetTester tester, String codigo) async {
  for (final c in codigo.split('')) {
    await simulateKeyDownEvent(
      LogicalKeyboardKey.digit0,
      character: c,
    );
    await simulateKeyUpEvent(LogicalKeyboardKey.digit0);
  }
  await simulateKeyDownEvent(LogicalKeyboardKey.enter);
  await simulateKeyUpEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  late List<String> escaneos;

  setUp(() => escaneos = <String>[]);

  /// Monta el listener dentro de una ruta, con un botón que permite abrir
  /// cosas encima (otra pantalla, un modal o un diálogo).
  Future<void> montar(
    WidgetTester tester, {
    bool enabled = true,
    required Future<void> Function(BuildContext context) abrirEncima,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HardwareScannerListener(
          enabled: enabled,
          onScanOverride: (_, code) => escaneos.add(code),
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const TextField(key: Key('campo')),
                  ElevatedButton(
                    onPressed: () => abrirEncima(context),
                    child: const Text('abrir'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> abrirYEscanear(
    WidgetTester tester,
    Future<void> Function(BuildContext) abrirEncima,
  ) async {
    await montar(tester, abrirEncima: abrirEncima);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await escanear(tester, '7501234');
  }

  testWidgets('procesa el escaneo cuando su ruta está al frente',
      (tester) async {
    await montar(tester, abrirEncima: (_) async {});

    await escanear(tester, '7501234567890');

    expect(escaneos, ['7501234567890']);
  });

  testWidgets('ignora el escaneo con otra pantalla encima', (tester) async {
    await abrirYEscanear(
      tester,
      (context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('otra pantalla')),
        ),
      ),
    );

    expect(escaneos, isEmpty);
  });

  testWidgets('ignora el escaneo con un bottom sheet encima', (tester) async {
    await abrirYEscanear(
      tester,
      (context) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 120, child: Text('hoja')),
      ),
    );

    expect(escaneos, isEmpty);
  });

  testWidgets('ignora el escaneo con un diálogo encima', (tester) async {
    await abrirYEscanear(
      tester,
      (context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('¿Vaciar carrito?')),
      ),
    );

    expect(escaneos, isEmpty);
  });

  testWidgets('vuelve a procesar al cerrar lo que estaba encima',
      (tester) async {
    await montar(
      tester,
      abrirEncima: (context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('diálogo')),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await escanear(tester, '111');
    expect(escaneos, isEmpty, reason: 'con el diálogo abierto no procesa');

    // Cerrar el diálogo tocando fuera (barrier).
    Navigator.of(tester.element(find.text('diálogo'))).pop();
    await tester.pumpAndSettle();

    await escanear(tester, '222');
    expect(escaneos, ['222']);
  });

  testWidgets('ignora el escaneo mientras un campo de texto tiene el foco',
      (tester) async {
    await montar(tester, abrirEncima: (_) async {});

    await tester.tap(find.byKey(const Key('campo')));
    await tester.pumpAndSettle();

    await escanear(tester, '333');

    expect(escaneos, isEmpty);
  });

  testWidgets('ignora el escaneo cuando está deshabilitado', (tester) async {
    await montar(tester, enabled: false, abrirEncima: (_) async {});

    await escanear(tester, '444');

    expect(escaneos, isEmpty);
  });
}
