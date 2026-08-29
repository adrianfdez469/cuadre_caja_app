import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/utils/app_route_observer.dart';

/// Réplica mínima de cómo la pantalla de venta usa el observer: suelta el foco
/// cuando le abren algo encima, para que al cerrarlo Flutter no se lo restaure
/// y vuelva a levantar el teclado.
class _PantallaConBuscador extends StatefulWidget {
  const _PantallaConBuscador({required this.abrirEncima});

  final Future<void> Function(BuildContext context) abrirEncima;

  @override
  State<_PantallaConBuscador> createState() => _PantallaConBuscadorState();
}

class _PantallaConBuscadorState extends State<_PantallaConBuscador>
    with RouteAware {
  final _focusNode = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get tieneFoco => _focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextField(focusNode: _focusNode),
          ElevatedButton(
            onPressed: () => widget.abrirEncima(context),
            child: const Text('abrir'),
          ),
        ],
      ),
    );
  }
}

void main() {
  /// Enfoca el buscador, abre algo encima, lo cierra, y devuelve si el foco
  /// volvió solo al buscador (que es lo que levantaba el teclado en móvil).
  Future<bool> focoTrasAbrirYCerrar(
    WidgetTester tester,
    Future<void> Function(BuildContext) abrirEncima,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: _PantallaConBuscador(abrirEncima: abrirEncima),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final estado = tester.state<_PantallaConBuscadorState>(
      find.byType(_PantallaConBuscador),
    );
    expect(estado.tieneFoco, isTrue, reason: 'el buscador arranca enfocado');

    // Se toma antes de abrir: con una pantalla completa encima, los widgets de
    // la ruta de abajo quedan offstage y `find` ya no los encuentra.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    navigator.pop();
    await tester.pumpAndSettle();

    return estado.tieneFoco;
  }

  testWidgets('no restaura el foco al volver de otra pantalla', (tester) async {
    final foco = await focoTrasAbrirYCerrar(
      tester,
      (context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('otra pantalla')),
        ),
      ),
    );

    expect(foco, isFalse);
  });

  testWidgets('no restaura el foco al cerrar un bottom sheet', (tester) async {
    final foco = await focoTrasAbrirYCerrar(
      tester,
      (context) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 120, child: Text('hoja')),
      ),
    );

    expect(foco, isFalse);
  });

  testWidgets('no restaura el foco al cerrar un diálogo', (tester) async {
    final foco = await focoTrasAbrirYCerrar(
      tester,
      (context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('diálogo')),
      ),
    );

    expect(foco, isFalse);
  });
}
