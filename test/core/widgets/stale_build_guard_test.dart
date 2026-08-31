import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/utils/apk_install_helper.dart';
import 'package:cuadre_caja_app/core/widgets/stale_build_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.example.cuadre_caja_app/native');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> nativeCalls;
  late Map<String, dynamic> staleResult;

  setUp(() {
    ApkInstallHelper.debugForceAndroidChannel = true;
    nativeCalls = [];
    staleResult = {'stale': false};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      nativeCalls.add(call.method);
      switch (call.method) {
        case 'checkStaleBuild':
          return staleResult;
        case 'closeApp':
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    ApkInstallHelper.debugForceAndroidChannel = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Monta el guard donde va en la app real: envolviendo al Navigator, para que
  /// el aviso tape también las rutas apiladas.
  Future<void> pumpGuard(
    WidgetTester tester, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        navigatorKey: navigatorKey,
        builder: (context, child) => StaleBuildGuard(child: child!),
        home: const Scaffold(body: Text('Punto de venta')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('con el APK intacto no se ve el aviso', (tester) async {
    await pumpGuard(tester);

    expect(find.text('Punto de venta'), findsOneWidget);
    expect(find.textContaining('Se instaló'), findsNothing);
    expect(nativeCalls, contains('checkStaleBuild'));
  });

  testWidgets('si el APK fue reemplazado avisa con la versión instalada',
      (tester) async {
    staleResult = {
      'stale': true,
      'runningVersionCode': 32,
      'installedVersionCode': 33,
      'installedVersionName': '2.4.0',
    };
    await pumpGuard(tester);

    expect(find.text('Se instaló la versión 2.4.0'), findsOneWidget);
    expect(find.text('Cerrar esta ventana'), findsOneWidget);
  });

  testWidgets('sin versionName instalada el aviso sigue siendo legible',
      (tester) async {
    staleResult = {'stale': true};
    await pumpGuard(tester);

    expect(find.text('Se instaló una versión nueva'), findsOneWidget);
  });

  testWidgets('el aviso tapa las rutas apiladas sobre home', (tester) async {
    staleResult = {'stale': true, 'installedVersionName': '2.4.0'};
    final navigator = GlobalKey<NavigatorState>();
    await pumpGuard(tester, navigatorKey: navigator);

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cobrar')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Se instaló la versión 2.4.0'), findsOneWidget);
    expect(find.text('Cerrar esta ventana'), findsOneWidget);
  });

  testWidgets('el botón cierra la app', (tester) async {
    staleResult = {'stale': true, 'installedVersionName': '2.4.0'};
    await pumpGuard(tester);

    await tester.tap(find.text('Cerrar esta ventana'));
    await tester.pump();

    expect(nativeCalls, contains('closeApp'));
    expect(find.text('Cerrando...'), findsOneWidget);
  });
}
