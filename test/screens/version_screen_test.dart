import 'dart:io';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/utils/apk_install_helper.dart';
import 'package:cuadre_caja_app/data/models/release_model.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';
import 'package:cuadre_caja_app/screens/version_screen.dart';
import 'package:cuadre_caja_app/services/release_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

const _channel = MethodChannel('com.example.cuadre_caja_app/native');

class _FakeVentasProvider extends Fake implements VentasProvider {
  @override
  int get pendingCount => 0;
}

/// ReleaseService falso que cuenta las descargas: la prueba de fuego de esta
/// feature es que `downloadApk` NO se llame cuando el APK ya está en disco.
class _FakeReleaseService extends Fake implements ReleaseService {
  _FakeReleaseService({this.downloadedApk});

  File? downloadedApk;
  int downloadCalls = 0;
  int cleanupCalls = 0;

  @override
  Future<ReleaseInfo?> fetchReleases({String? releasesFileId}) async =>
      const ReleaseInfo(version: '2.0.2', apks: {'arm64-v8a': 'file-id'});

  @override
  String? getApkVariantKeyForDevice(ReleaseInfo release, {String? androidAbi}) =>
      'arm64-v8a';

  @override
  Future<File?> findDownloadedApk({
    required String version,
    required String variantKey,
  }) async =>
      downloadedApk;

  @override
  Future<int> cleanupApks({String? keepFileName}) async {
    cleanupCalls++;
    return 0;
  }

  @override
  Future<File?> downloadApk(
    String fileId, {
    required String version,
    required String variantKey,
    void Function(int, int)? onProgress,
  }) async {
    downloadCalls++;
    return downloadedApk;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El fake implementa VentasProvider (un ChangeNotifier) sin serlo realmente;
  // la pantalla solo hace `read`, así que basta un Provider simple.
  Provider.debugCheckInvalidValueType = null;

  late Directory dir;
  late File apk;
  late List<String> nativeCalls;
  late bool permisoConcedido;
  late Map<String, dynamic> validation;

  setUp(() {
    ApkInstallHelper.debugForceAndroidChannel = true;
    PackageInfo.setMockInitialValues(
      appName: 'Cuadre de Caja',
      packageName: 'com.example.cuadre_caja_app',
      version: '2.0.1',
      buildNumber: '28',
      buildSignature: '',
    );

    dir = Directory.systemTemp.createTempSync('version_screen_test');
    apk = File('${dir.path}/update_2.0.2_arm64-v8a.apk')
      ..writeAsBytesSync([0x50, 0x4B, ...List<int>.filled(150 * 1024, 0x41)]);

    nativeCalls = [];
    permisoConcedido = true;
    validation = {'canInstall': true};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      nativeCalls.add(call.method);
      switch (call.method) {
        case 'getAndroidAbi':
          return 'arm64-v8a';
        case 'canInstallFromUnknownSources':
          return permisoConcedido;
        case 'validateApkForUpdate':
          return validation;
        case 'installApk':
          return true;
        case 'openUnknownSourcesSettings':
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    ApkInstallHelper.debugForceAndroidChannel = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Tras lanzar el instalador la pantalla se queda con un spinner ("Abriendo
  /// instalador..."), porque en un dispositivo real el proceso muere ahí.
  /// `pumpAndSettle` nunca terminaría, así que se bombean frames sueltos.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpScreen(WidgetTester tester, _FakeReleaseService service) async {
    await tester.pumpWidget(
      Provider<VentasProvider>.value(
        value: _FakeVentasProvider(),
        child: MaterialApp(
          theme: appLightTheme,
          home: VersionScreen(releaseService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('con un APK ya descargado ofrece instalar y no descarga nada',
      (tester) async {
    final service = _FakeReleaseService(downloadedApk: apk);

    await pumpScreen(tester, service);

    expect(find.text('Instalar ahora'), findsOneWidget);
    expect(find.text('Actualizar aplicación'), findsNothing);
    expect(service.downloadCalls, 0);
    expect(
      find.textContaining('ya está descargado'),
      findsOneWidget,
    );
  });

  testWidgets('sin descarga previa ofrece descargar y descarga una vez',
      (tester) async {
    final service = _FakeReleaseService();

    await pumpScreen(tester, service);
    expect(find.text('Actualizar aplicación'), findsOneWidget);

    service.downloadedApk = apk;
    await tester.tap(find.text('Actualizar aplicación'));
    await pumpFrames(tester);

    expect(service.downloadCalls, 1);
    expect(nativeCalls, contains('installApk'));
  });

  testWidgets('si falta el permiso conserva el APK descargado', (tester) async {
    validation = {'canInstall': false, 'reason': 'unknown_sources_blocked'};
    final service = _FakeReleaseService(downloadedApk: apk);

    await pumpScreen(tester, service);
    await tester.tap(find.text('Instalar ahora'));
    await tester.pumpAndSettle();

    expect(find.text('Permiso necesario'), findsOneWidget);
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();

    expect(nativeCalls, contains('openUnknownSourcesSettings'));
    expect(nativeCalls, isNot(contains('installApk')));
    // El estado no se pierde: sigue habiendo un APK listo para instalar.
    expect(find.text('Instalar ahora'), findsOneWidget);
    expect(service.downloadCalls, 0);
    expect(find.textContaining('continuará automáticamente'), findsOneWidget);
  });

  testWidgets('al volver con el permiso concedido instala sin volver a descargar',
      (tester) async {
    validation = {'canInstall': false, 'reason': 'unknown_sources_blocked'};
    final service = _FakeReleaseService(downloadedApk: apk);

    await pumpScreen(tester, service);
    await tester.tap(find.text('Instalar ahora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();

    // El usuario concede el permiso en Ajustes y vuelve a la app.
    permisoConcedido = true;
    validation = {'canInstall': true};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFrames(tester);

    expect(nativeCalls.where((c) => c == 'installApk').length, 1);
    expect(service.downloadCalls, 0);
  });

  testWidgets('varios resumes seguidos no lanzan el instalador más de una vez',
      (tester) async {
    validation = {'canInstall': false, 'reason': 'unknown_sources_blocked'};
    final service = _FakeReleaseService(downloadedApk: apk);

    await pumpScreen(tester, service);
    await tester.tap(find.text('Instalar ahora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();

    permisoConcedido = true;
    validation = {'canInstall': true};
    for (var i = 0; i < 3; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
    }

    expect(nativeCalls.where((c) => c == 'installApk').length, 1);
    expect(service.downloadCalls, 0);
  });

  testWidgets('un resume sin el permiso concedido no instala ni molesta',
      (tester) async {
    validation = {'canInstall': false, 'reason': 'unknown_sources_blocked'};
    final service = _FakeReleaseService(downloadedApk: apk);

    await pumpScreen(tester, service);
    await tester.tap(find.text('Instalar ahora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();

    permisoConcedido = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(nativeCalls, isNot(contains('installApk')));
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Instalar ahora'), findsOneWidget);
  });

  testWidgets('un APK corrupto en disco vuelve a ofrecer la descarga',
      (tester) async {
    final corrupto = File('${dir.path}/corrupto.apk')
      ..writeAsBytesSync([0x50, 0x4B, 0x03]);
    final service = _FakeReleaseService(downloadedApk: corrupto);

    await pumpScreen(tester, service);
    await tester.tap(find.text('Instalar ahora'));
    await tester.pumpAndSettle();

    expect(nativeCalls, isNot(contains('installApk')));
    expect(find.text('Actualizar aplicación'), findsOneWidget);
  });
}
