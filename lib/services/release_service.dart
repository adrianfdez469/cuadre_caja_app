import 'dart:convert';
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
      return ReleaseInfo.fromJson(data);
    } catch (e) {
      print('ReleaseService.fetchReleases error: $e');
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
      print('ReleaseService.fetchRoadmap error: $e');
      return release;
    }
  }

  /// Devuelve el fileId del APK adecuado para este dispositivo.
  /// [androidAbi] debe ser uno de: arm64-v8a, armeabi-v7a, x86_64. Si no coincide, usa "universal".
  String? getApkFileIdForDevice(ReleaseInfo release, {String? androidAbi}) {
    if (release.apks.isEmpty) return null;
    if (androidAbi != null && release.apks.containsKey(androidAbi)) {
      return release.apks[androidAbi];
    }
    return release.apks['universal'] ??
        release.apks['arm64-v8a'] ??
        release.apks['armeabi-v7a'] ??
        release.apks['x86_64'] ??
        release.apks.values.firstOrNull;
  }

  /// Descarga el APK al directorio temporal y devuelve el File.
  /// Usa la URL para archivos grandes para evitar la página de advertencia de Drive (~2 KB).
  Future<File?> downloadApk(String fileId, {void Function(int, int)? onProgress}) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/update_${DateTime.now().millisecondsSinceEpoch}.apk';
      await _dio.download(
        driveDownloadUrlLarge(fileId),
        path,
        onReceiveProgress: onProgress,
      );
      final f = File(path);
      if (!f.existsSync()) return null;
      // Si el archivo es muy pequeño, Drive devolvió HTML en lugar del APK
      final len = f.lengthSync();
      if (len < 100 * 1024) {
        f.deleteSync();
        print('ReleaseService.downloadApk: file too small ($len bytes), likely Drive warning page');
        return null;
      }
      return f;
    } catch (e) {
      print('ReleaseService.downloadApk error: $e');
      return null;
    }
  }
}
