import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cuadre_caja_app/data/models/release_model.dart';
import 'package:cuadre_caja_app/services/release_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// path_provider apuntando a directorios temporales reales. No se mockea el
/// MethodChannel porque el plugin de Android usa Pigeon: la costura correcta es
/// la platform interface.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportPath, this.tempPath);

  final String supportPath;
  final String tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

/// Adapter que devuelve los bytes indicados, o lanza a mitad de la descarga
/// para simular una conexión que se cae.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.failAfterBytes});

  final List<int> body;
  final int? failAfterBytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (failAfterBytes == null) {
      return ResponseBody.fromBytes(body, 200);
    }
    Stream<Uint8List> chunks() async* {
      yield Uint8List.fromList(body.sublist(0, failAfterBytes!));
      throw const SocketException('conexión perdida');
    }

    return ResponseBody(chunks(), 200, headers: {
      Headers.contentLengthHeader: [body.length.toString()],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Bytes que `looksLikeApk` acepta: cabecera ZIP y ≥100 KB.
List<int> _apkBytes({int size = 150 * 1024}) =>
    [0x50, 0x4B, ...List<int>.filled(size - 2, 0x41)];

void main() {
  late Directory root;
  late Directory support;
  late Directory temp;
  late ReleaseService service;

  ReleaseService serviceWith(HttpClientAdapter adapter) =>
      ReleaseService(dio: Dio()..httpClientAdapter = adapter);

  setUp(() {
    root = Directory.systemTemp.createTempSync('release_service_test');
    support = Directory('${root.path}/support')..createSync();
    temp = Directory('${root.path}/temp')..createSync();
    PathProviderPlatform.instance = _FakePathProvider(support.path, temp.path);
    service = serviceWith(_FakeAdapter(_apkBytes()));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File updatesFile(String name) =>
      File('${support.path}/updates/$name');

  group('apkFileNameFor', () {
    test('es determinista y depende de versión y variante', () {
      final a = ReleaseService.apkFileNameFor(
          version: '2.0.2', variantKey: 'arm64-v8a');
      expect(a, 'update_2.0.2_arm64-v8a.apk');
      expect(
        ReleaseService.apkFileNameFor(version: '2.0.2', variantKey: 'arm64-v8a'),
        a,
      );
      expect(
        ReleaseService.apkFileNameFor(version: '2.0.3', variantKey: 'arm64-v8a'),
        isNot(a),
      );
      expect(
        ReleaseService.apkFileNameFor(version: '2.0.2', variantKey: 'universal'),
        isNot(a),
      );
    });

    test('sanea caracteres que no valen en un nombre de archivo', () {
      final name = ReleaseService.apkFileNameFor(
          version: '2.0/2 beta', variantKey: 'arm64 v8a');
      expect(name, 'update_2.0_2_beta_arm64_v8a.apk');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(' ')));
    });
  });

  group('getApkVariantKeyForDevice', () {
    ReleaseInfo release(Map<String, String> apks) =>
        ReleaseInfo(version: '2.0.2', apks: apks);

    test('usa la ABI del dispositivo cuando está disponible', () {
      final r = release({'arm64-v8a': 'id-arm', 'universal': 'id-uni'});
      expect(
        service.getApkVariantKeyForDevice(r, androidAbi: 'arm64-v8a'),
        'arm64-v8a',
      );
      expect(
        service.getApkFileIdForDevice(r, androidAbi: 'arm64-v8a'),
        'id-arm',
      );
    });

    test('cae a universal cuando la ABI no está publicada', () {
      final r = release({'universal': 'id-uni', 'x86_64': 'id-x86'});
      expect(
        service.getApkVariantKeyForDevice(r, androidAbi: 'armeabi-v7a'),
        'universal',
      );
    });

    test('sigue la cadena de fallback cuando no hay universal', () {
      final r = release({'x86_64': 'id-x86', 'armeabi-v7a': 'id-v7a'});
      expect(
        service.getApkVariantKeyForDevice(r, androidAbi: 'arm64-v8a'),
        'armeabi-v7a',
      );
    });

    test('devuelve null sin APKs publicados', () {
      expect(service.getApkVariantKeyForDevice(release({})), isNull);
      expect(service.getApkFileIdForDevice(release({})), isNull);
    });
  });

  group('downloadApk', () {
    test('deja el APK con nombre determinista y ningún .part', () async {
      final file = await service.downloadApk(
        'file-id',
        version: '2.0.2',
        variantKey: 'arm64-v8a',
      );

      expect(file, isNotNull);
      expect(file!.path, endsWith('update_2.0.2_arm64-v8a.apk'));
      expect(file.lengthSync(), 150 * 1024);
      final leftovers = Directory('${support.path}/updates')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.endsWith('.part'));
      expect(leftovers, isEmpty);
    });

    test('una descarga interrumpida no deja APK reutilizable', () async {
      final s = serviceWith(_FakeAdapter(_apkBytes(), failAfterBytes: 40 * 1024));

      final file = await s.downloadApk(
        'file-id',
        version: '2.0.2',
        variantKey: 'arm64-v8a',
      );

      expect(file, isNull);
      expect(updatesFile('update_2.0.2_arm64-v8a.apk').existsSync(), isFalse);
      expect(
        updatesFile('update_2.0.2_arm64-v8a.apk.part').existsSync(),
        isFalse,
      );
      expect(
        await s.findDownloadedApk(version: '2.0.2', variantKey: 'arm64-v8a'),
        isNull,
      );
    });

    test('descarta la página de aviso HTML de Drive', () async {
      final s = serviceWith(_FakeAdapter(List<int>.filled(2 * 1024, 0x3C)));

      final file = await s.downloadApk(
        'file-id',
        version: '2.0.2',
        variantKey: 'arm64-v8a',
      );

      expect(file, isNull);
      expect(updatesFile('update_2.0.2_arm64-v8a.apk').existsSync(), isFalse);
    });
  });

  group('findDownloadedApk', () {
    test('encuentra una descarga previa válida', () async {
      await service.downloadApk(
        'file-id',
        version: '2.0.2',
        variantKey: 'arm64-v8a',
      );

      final found = await service.findDownloadedApk(
        version: '2.0.2',
        variantKey: 'arm64-v8a',
      );

      expect(found, isNotNull);
      expect(found!.existsSync(), isTrue);
    });

    test('borra y descarta un archivo truncado', () async {
      Directory('${support.path}/updates').createSync(recursive: true);
      final f = updatesFile('update_2.0.2_arm64-v8a.apk')
        ..writeAsBytesSync([0x50, 0x4B, 0x03]);

      final found = await service.findDownloadedApk(
        version: '2.0.2',
        variantKey: 'arm64-v8a',
      );

      expect(found, isNull);
      expect(f.existsSync(), isFalse);
    });

    test('devuelve null si no hay nada descargado', () async {
      expect(
        await service.findDownloadedApk(version: '2.0.2', variantKey: 'universal'),
        isNull,
      );
    });
  });

  group('cleanupApks', () {
    setUp(() {
      Directory('${support.path}/updates').createSync(recursive: true);
      updatesFile('update_2.0.2_arm64-v8a.apk').writeAsBytesSync(_apkBytes());
      updatesFile('update_1.0.0_arm64-v8a.apk').writeAsBytesSync(_apkBytes());
      updatesFile('update_2.0.2_universal.apk.part').writeAsBytesSync([1, 2, 3]);
      updatesFile('otro_archivo.txt').writeAsStringSync('no tocar');
      File('${temp.path}/update_1699999999999.apk').writeAsBytesSync(_apkBytes());
    });

    test('conserva el APK vigente y borra el resto, incluido el temporal legacy',
        () async {
      final deleted = await service.cleanupApks(
        keepFileName: 'update_2.0.2_arm64-v8a.apk',
      );

      expect(deleted, 3);
      expect(updatesFile('update_2.0.2_arm64-v8a.apk').existsSync(), isTrue);
      expect(updatesFile('update_1.0.0_arm64-v8a.apk').existsSync(), isFalse);
      expect(updatesFile('update_2.0.2_universal.apk.part').existsSync(), isFalse);
      expect(File('${temp.path}/update_1699999999999.apk').existsSync(), isFalse);
    });

    test('sin keepFileName borra todos los APK descargados', () async {
      await service.cleanupApks();

      expect(updatesFile('update_2.0.2_arm64-v8a.apk').existsSync(), isFalse);
      expect(updatesFile('update_1.0.0_arm64-v8a.apk').existsSync(), isFalse);
    });

    test('no toca archivos ajenos al patrón', () async {
      await service.cleanupApks();

      expect(updatesFile('otro_archivo.txt').existsSync(), isTrue);
    });
  });
}
