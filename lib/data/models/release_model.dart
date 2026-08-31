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

  /// Mejoras para una versión (ej. v0.0.3), ya formateadas como
  /// "Categoría: texto". Para pintar la categoría aparte usa
  /// [getChangelogItems].
  List<String> getChangelogEntries(String versionKey) =>
      getChangelogItems(versionKey).map((i) => i.label).toList();

  /// Mejoras de una versión con la categoría separada del texto. Cada item del
  /// JSON es un mapa de una sola clave (ej. {"Arreglos": "bla"}).
  List<ChangelogItem> getChangelogItems(String versionKey) {
    final key = versionKey.startsWith('v') ? versionKey : 'v$versionKey';
    final list = changelog[key] ?? [];
    return list
        .where((m) => m.isNotEmpty && m.entries.first.value.trim().isNotEmpty)
        .map((m) => ChangelogItem(
              categoria: m.entries.first.key,
              texto: m.entries.first.value,
            ))
        .toList();
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
  ) =>
      _sections(compare, (k) => compare(k, currentVersion) > 0);

  /// Historial completo publicado en releases.json, de la versión más reciente a
  /// la más antigua. Es lo que alimenta la pantalla de "Novedades": a diferencia
  /// de [getChangelogSince], incluye la versión instalada y las anteriores.
  List<VersionChangelog> getAllChangelog(int Function(String, String) compare) =>
      _sections(compare, (_) => true);

  List<VersionChangelog> _sections(
    int Function(String, String) compare,
    bool Function(String key) incluir,
  ) {
    final keys = changelog.keys.where(incluir).toList()
      ..sort((a, b) => compare(b, a));
    return keys
        .map((k) => VersionChangelog(
              version: k.replaceFirst(RegExp(r'^v'), ''),
              items: getChangelogItems(k),
            ))
        .where((c) => c.items.isNotEmpty)
        .toList();
  }
}

/// Una mejora concreta del changelog: su categoría ("Mejoras", "Arreglos",
/// "Caracteristicas") y el texto que lee el usuario.
class ChangelogItem {
  final String categoria;
  final String texto;

  const ChangelogItem({required this.categoria, required this.texto});

  String get label => '$categoria: $texto';
}

/// Changelog de una versión concreta (para mostrar versiones intermedias).
class VersionChangelog {
  final String version;
  final List<ChangelogItem> items;

  const VersionChangelog({required this.version, required this.items});

  /// Entradas ya formateadas como "Categoría: texto".
  List<String> get entries => items.map((i) => i.label).toList();
}
