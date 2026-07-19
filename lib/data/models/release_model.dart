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

  /// Changelog acumulado de todas las versiones más nuevas que [currentVersion],
  /// ordenado de la más reciente a la más antigua. Cuando el usuario está varias
  /// versiones atrasado, permite mostrar los cambios de cada versión intermedia,
  /// no solo los de la última. [compare] debe devolver >0 si su primer argumento
  /// es una versión mayor (p. ej. `compareVersions` de release_service).
  ///
  /// Cada elemento es la versión normalizada (ej. `1.1.8`) con sus entradas de
  /// changelog; se omiten las versiones sin entradas.
  List<VersionChangelog> getChangelogSince(
    String currentVersion,
    int Function(String, String) compare,
  ) {
    final keys = changelog.keys
        .where((k) => compare(k, currentVersion) > 0)
        .toList()
      ..sort((a, b) => compare(b, a));
    return keys
        .map((k) => VersionChangelog(
              version: k.replaceFirst(RegExp(r'^v'), ''),
              entries: getChangelogEntries(k),
            ))
        .where((c) => c.entries.isNotEmpty)
        .toList();
  }
}

/// Changelog de una versión concreta (para mostrar versiones intermedias).
class VersionChangelog {
  final String version;
  final List<String> entries;

  const VersionChangelog({required this.version, required this.entries});
}
