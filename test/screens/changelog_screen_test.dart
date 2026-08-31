import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/release_model.dart';
import 'package:cuadre_caja_app/screens/changelog_screen.dart';
import 'package:cuadre_caja_app/services/release_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _release = ReleaseInfo.fromJson({
  'version': '2.2.0',
  'apks': {'arm64-v8a': 'id1'},
  'changelog': {
    'v2.2.0': [
      {'Mejoras': 'El POS abre mas rapido'},
    ],
    'v2.1.0': [
      {'Arreglos': 'Se arregla la anulacion sin conexion'},
    ],
  },
});

/// ReleaseService falso: permite simular "hay red" y "no hay red pero sí caché".
class _FakeReleaseService extends Fake implements ReleaseService {
  _FakeReleaseService({this.remoto, this.cache});

  final ReleaseInfo? remoto;
  final ReleaseInfo? cache;
  int fetchCalls = 0;

  @override
  Future<ReleaseInfo?> fetchReleases({String? releasesFileId}) async {
    fetchCalls++;
    return remoto;
  }

  @override
  Future<ReleaseInfo?> loadCachedReleases() async => cache;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: appLightTheme, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista la versión instalada y las anteriores, de nueva a antigua',
      (tester) async {
    await _pump(
      tester,
      ChangelogScreen(currentVersion: '2.2.0', release: _release),
    );

    expect(find.text('v2.2.0'), findsOneWidget);
    expect(find.text('v2.1.0'), findsOneWidget);
    expect(find.text('El POS abre mas rapido'), findsOneWidget);
    expect(find.text('Se arregla la anulacion sin conexion'), findsOneWidget);

    final orden = tester.widgetList<Text>(find.byType(Text)).toList();
    final iActual = orden.indexWhere((t) => t.data == 'v2.2.0');
    final iAnterior = orden.indexWhere((t) => t.data == 'v2.1.0');
    expect(iActual, lessThan(iAnterior));
  });

  testWidgets('marca cuál es la versión instalada', (tester) async {
    await _pump(
      tester,
      ChangelogScreen(currentVersion: '2.1.0', release: _release),
    );

    expect(find.text('Tu versión'), findsOneWidget);
    // La 2.2.0 todavía no está instalada: se anuncia como disponible.
    expect(find.text('Disponible'), findsOneWidget);
  });

  testWidgets('sin datos previos los pide a la red', (tester) async {
    final service = _FakeReleaseService(remoto: _release);

    await _pump(
      tester,
      ChangelogScreen(
        currentVersion: '2.2.0',
        releaseService: service,
      ),
    );

    expect(service.fetchCalls, 1);
    expect(find.text('v2.1.0'), findsOneWidget);
  });

  testWidgets('sin conexión cae a la copia guardada y lo avisa', (tester) async {
    await _pump(
      tester,
      ChangelogScreen(
        currentVersion: '2.2.0',
        releaseService: _FakeReleaseService(cache: _release),
      ),
    );

    expect(find.text('v2.2.0'), findsOneWidget);
    expect(
      find.textContaining('se muestra el historial guardado'),
      findsOneWidget,
    );
  });

  testWidgets('sin red ni caché explica qué hacer y deja reintentar',
      (tester) async {
    await _pump(
      tester,
      ChangelogScreen(
        currentVersion: '2.2.0',
        releaseService: _FakeReleaseService(),
      ),
    );

    expect(find.textContaining('Todavía no hay historial'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
