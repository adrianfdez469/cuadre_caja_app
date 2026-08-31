import 'dart:async';
import 'dart:convert';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../data/models/release_model.dart';

/// URL directa de descarga para un archivo de Drive (compartido "cualquiera con el enlace").
/// Para JSON y archivos pequeños.
String driveDownloadUrl(String fileId) =>
    'https://drive.google.com/uc?export=download&id=$fileId';

/// URL que evita la página de advertencia de virus en archivos grandes (APK, etc.).
/// Ver https://stackoverflow.com/questions/48133080/how-to-download-a-google-drive-url-via-curl-or-wget
String driveDownloadUrlLarge(String fileId) =>
    'https://drive.usercontent.google.com/download?id=$fileId&export=download&confirm=t';

/// Compara versiones semver (ej. "0.0.3" vs "1.0.0"). Devuelve <0 si a<b, 0 si a==b, >0 si a>b.
int compareVersions(String a, String b) {
  final na = _parseVersion(a);
  final nb = _parseVersion(b);
  for (var i = 0; i < 3; i++) {
    final va = i < na.length ? na[i] : 0;
    final vb = i < nb.length ? nb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _parseVersion(String v) {
  final s = v.replaceFirst(RegExp(r'^v'), '').trim();
  return s.split('.').map((e) => int.tryParse(e) ?? 0).toList();
}

/// Servicio para obtener releases desde Drive y descargar APK.
class ReleaseService {
  ReleaseService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Obtiene la información de releases desde Drive (releases.json).
  /// Si [releasesFileId] está vacío usa [AppConstants.driveReleasesJsonFileId].
  Future<ReleaseInfo?> fetchReleases({String? releasesFileId}) async {
    final fileId = releasesFileId?.isNotEmpty == true
        ? releasesFileId!
        : AppConstants.driveReleasesJsonFileId;
    if (fileId.isEmpty) return null;
    try {
      final response = await _dio.get<String>(
        driveDownloadUrl(fileId),
        options: Options(responseType: ResponseType.plain),
      );
      if (response.data == null) return null;
      final json = response.data!;
      final trimmed = json.trim();
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      final body = start >= 0 && end > start ? trimmed.substring(start, end + 1) : trimmed;
      final data = jsonDecode(body) as Map<String, dynamic>?;
      if (data == null) return null;
      final release = ReleaseInfo.fromJson(data);
      // El historial de novedades tiene que poder verse sin conexión: se guarda
      // la última respuesta buena para leerla cuando Drive no esté disponible.
      unawaited(_cacheReleasesJson(body));
      return release;
    } catch (e) {
      logDebug('ReleaseService.fetchReleases error: $e');
      return null;
    }
  }

  /// Nombre del archivo con la última copia buena de releases.json.
  static const _releasesCacheFileName = 'releases_cache.json';

  Future<File> _releasesCacheFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/$_releasesCacheFileName');
  }

  Future<void> _cacheReleasesJson(String body) async {
    try {
      final file = await _releasesCacheFile();
      await file.writeAsString(body, flush: true);
    } catch (e) {
      // Que no se pueda cachear no debe romper la comprobación de versiones.
      logDebug('ReleaseService.cacheReleases error: $e');
    }
  }

  /// Última copia de releases.json guardada en el equipo, o null si nunca se
  /// descargó. Solo alimenta el historial de novedades: la comprobación de
  /// actualizaciones sigue exigiendo datos frescos.
  Future<ReleaseInfo?> loadCachedReleases() async {
    try {
      final file = await _releasesCacheFile();
      if (!file.existsSync()) return null;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>?;
      if (data == null) return null;
      return ReleaseInfo.fromJson(data);
    } catch (e) {
      logDebug('ReleaseService.loadCachedReleases error: $e');
      return null;
    }
  }

  /// Obtiene el roadmap (changelog) desde roadmap.json y lo fusiona en [release].
  Future<ReleaseInfo> fetchRoadmapAndMerge(
    ReleaseInfo release, {
    String? roadmapFileId,
  }) async {
    final fileId = roadmapFileId?.isNotEmpty == true
        ? roadmapFileId!
        : AppConstants.driveRoadmapJsonFileId;
    if (fileId.isEmpty) return release;
    try {
      final response = await _dio.get<String>(
        driveDownloadUrl(fileId),
        options: Options(responseType: ResponseType.plain),
      );
      if (response.data == null) return release;
      final data = jsonDecode(response.data!) as Map<String, dynamic>?;
      if (data == null) return release;
      final newChangelog = <String, List<Map<String, String>>>{};
      for (final e in data.entries) {
        final list = e.value is List ? e.value as List : <dynamic>[];
        newChangelog[e.key] = list
            .map((item) => (item is Map ? item as Map<String, dynamic> : <String, dynamic>{})
                .map((k, v) => MapEntry(k, v?.toString() ?? '')))
            .toList();
      }
      return ReleaseInfo(
        version: release.version,
        apks: release.apks,
        changelog: newChangelog,
      );
    } catch (e) {
      logDebug('ReleaseService.fetchRoadmap error: $e');
      return release;
    }
  }

  /// Devuelve la clave de la variante de APK que corresponde a este dispositivo
  /// ("arm64-v8a", "universal", ...). Está separada de [getApkFileIdForDevice]
  /// porque el archivo local se nombra por la variante realmente servida, que no
  /// tiene por qué coincidir con la ABI del dispositivo (ej. un teléfono arm64
  /// al que solo se le ofrece el APK "universal").
  /// [androidAbi] debe ser uno de: arm64-v8a, armeabi-v7a, x86_64.
  String? getApkVariantKeyForDevice(ReleaseInfo release, {String? androidAbi}) {
    if (release.apks.isEmpty) return null;
    if (androidAbi != null && release.apks.containsKey(androidAbi)) {
      return androidAbi;
    }
    for (final key in const ['universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      if (release.apks.containsKey(key)) return key;
    }
    return release.apks.keys.firstOrNull;
  }

  /// Devuelve el fileId del APK adecuado para este dispositivo.
  String? getApkFileIdForDevice(ReleaseInfo release, {String? androidAbi}) {
    final key = getApkVariantKeyForDevice(release, androidAbi: androidAbi);
    return key == null ? null : release.apks[key];
  }

  /// Verifica que un archivo descargado parece un APK válido (cabecera ZIP + tamaño mínimo).
  static bool looksLikeApk(File file) {
    if (!file.existsSync()) return false;
    if (file.lengthSync() < 100 * 1024) return false;
    try {
      final raf = file.openSync(mode: FileMode.read);
      final header = raf.readSync(2);
      raf.closeSync();
      return header.length == 2 && header[0] == 0x50 && header[1] == 0x4B;
    } catch (_) {
      return false;
    }
  }

  /// Subcarpeta de `getApplicationSupportDirectory()` donde vive el APK
  /// descargado. Se usa almacenamiento de datos y no el temporal porque el
  /// sistema puede vaciar la caché en cualquier momento y perderíamos una
  /// descarga de decenas de MB. En Android `applicationSupport` es
  /// `context.getFilesDir()`, ya cubierto por el `<files-path>` de
  /// `res/xml/file_paths.xml`, así que el FileProvider puede servirlo al
  /// instalador sin tocar nada nativo.
  static const _apkSubdir = 'updates';

  /// Prefijo de los APK descargados. Sirve también para reconocer los archivos
  /// que hay que barrer, incluidos los `update_<millis>.apk` que las versiones
  /// anteriores dejaban en el directorio temporal.
  static const _apkPrefix = 'update_';

  /// `<applicationSupport>/updates`, creado si no existe.
  Future<Directory> apkStorageDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_apkSubdir');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Nombre determinista del APK de una versión y variante concretas. Al no
  /// depender de la hora de descarga, una descarga anterior se puede localizar
  /// y reutilizar (p. ej. tras mandar al usuario a conceder el permiso de
  /// instalar apps desconocidas).
  static String apkFileNameFor({
    required String version,
    required String variantKey,
  }) {
    final v = _sanitizeForFileName(version);
    final k = _sanitizeForFileName(variantKey);
    return '$_apkPrefix${v}_$k.apk';
  }

  static String _sanitizeForFileName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Devuelve el APK ya descargado para [version]/[variantKey] si sigue en disco
  /// y parece válido. Si el archivo existe pero está truncado o corrupto lo borra
  /// y devuelve null, para que la pantalla ofrezca descargarlo de nuevo.
  Future<File?> findDownloadedApk({
    required String version,
    required String variantKey,
  }) async {
    try {
      final dir = await apkStorageDir();
      final f = File(
        '${dir.path}/${apkFileNameFor(version: version, variantKey: variantKey)}',
      );
      if (!f.existsSync()) return null;
      if (!looksLikeApk(f)) {
        f.deleteSync();
        logDebug('ReleaseService.findDownloadedApk: archivo inválido, borrado');
        return null;
      }
      return f;
    } catch (e) {
      logDebug('ReleaseService.findDownloadedApk error: $e');
      return null;
    }
  }

  /// Borra los APK descargados que ya no sirven: todo `update_*` de
  /// `<applicationSupport>/updates` salvo [keepFileName], las descargas a medias
  /// (`.part`) y los `update_<millis>.apk` que quedaron en el directorio temporal
  /// con el esquema anterior. Devuelve cuántos archivos borró; nunca lanza.
  Future<int> cleanupApks({String? keepFileName}) async {
    var deleted = 0;
    Future<void> sweep(Directory dir, {String? keep}) async {
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(_apkPrefix)) continue;
        if (!name.endsWith('.apk') && !name.endsWith('.part')) continue;
        if (keep != null && name == keep) continue;
        try {
          entity.deleteSync();
          deleted++;
        } catch (e) {
          logDebug('ReleaseService.cleanupApks: no se pudo borrar $name: $e');
        }
      }
    }

    try {
      await sweep(await apkStorageDir(), keep: keepFileName);
    } catch (e) {
      logDebug('ReleaseService.cleanupApks (updates) error: $e');
    }
    try {
      await sweep(await getTemporaryDirectory());
    } catch (e) {
      logDebug('ReleaseService.cleanupApks (temp) error: $e');
    }
    return deleted;
  }

  /// Descarga el APK de [version]/[variantKey] y devuelve el File.
  /// Usa la URL para archivos grandes para evitar la página de advertencia de Drive (~2 KB).
  ///
  /// La descarga va a un `.part` que solo se renombra al nombre definitivo tras
  /// validarlo: así una descarga interrumpida nunca se confunde con un APK
  /// reutilizable.
  Future<File?> downloadApk(
    String fileId, {
    required String version,
    required String variantKey,
    void Function(int, int)? onProgress,
  }) async {
    File? part;
    try {
      final dir = await apkStorageDir();
      final name = apkFileNameFor(version: version, variantKey: variantKey);
      final target = File('${dir.path}/$name');
      part = File('${target.path}.part');
      if (part.existsSync()) part.deleteSync();

      await _dio.download(
        driveDownloadUrlLarge(fileId),
        part.path,
        onReceiveProgress: onProgress,
      );

      if (!part.existsSync() || !looksLikeApk(part)) {
        if (part.existsSync()) part.deleteSync();
        logDebug('ReleaseService.downloadApk: invalid APK file (bad header or too small)');
        return null;
      }
      if (target.existsSync()) target.deleteSync();
      return await part.rename(target.path);
    } catch (e) {
      logDebug('ReleaseService.downloadApk error: $e');
      try {
        if (part != null && part.existsSync()) part.deleteSync();
      } catch (_) {}
      return null;
    }
  }
}
