/// Modelo del archivo releases.json en Drive.
/// Formato esperado: { "version": "0.0.3", "apks": { "arm64-v8a": "fileId", ... }, "changelog": { "v0.0.3": [...], ... } }
class ReleaseInfo {
  final String version;
  final Map<String, String> apks;
  final Map<String, List<Map<String, String>>> changelog;

  const ReleaseInfo({
    required this.version,
    required this.apks,
    this.changelog = const {},
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final apksRaw = json['apks'] as Map<String, dynamic>? ?? {};
    final apks = apksRaw.map((k, v) => MapEntry(k, v?.toString() ?? ''));

    final changelogRaw = json['changelog'] as Map<String, dynamic>? ?? {};
    final changelog = <String, List<Map<String, String>>>{};
    for (final e in changelogRaw.entries) {
      final list = e.value is List ? e.value as List : <dynamic>[];
      changelog[e.key] = list
          .map((item) {
            final m = item is Map ? item : <String, dynamic>{};
            return m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          })
          .toList();
    }

    return ReleaseInfo(
      version: (json['version'] ?? '').toString().replaceFirst(RegExp(r'^v'), ''),
      apks: apks,
      changelog: changelog,
    );
  }

  /// Mejoras para una versión (ej. v0.0.3). Cada item es un mapa con una sola clave (ej. {"arreglo": "bla"}).
  List<String> getChangelogEntries(String versionKey) {
    final key = versionKey.startsWith('v') ? versionKey : 'v$versionKey';
    final list = changelog[key] ?? [];
    return list.map((m) {
      if (m.isEmpty) return '';
      final entry = m.entries.first;
      return '${entry.key}: ${entry.value}';
    }).where((s) => s.isNotEmpty).toList();
  }
}
