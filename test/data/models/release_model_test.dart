import 'package:cuadre_caja_app/data/models/release_model.dart';
import 'package:cuadre_caja_app/services/release_service.dart' show compareVersions;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = ReleaseInfo.fromJson({
    'version': '1.1.8',
    'apks': {'arm64-v8a': 'id1'},
    'changelog': {
      'v1.1.8': [
        {'Mejoras': 'Comprobación automática de actualizaciones'},
      ],
      'v1.1.7': [
        {'Arreglos': 'Se corrige el vuelto en moneda extranjera'},
        {'Mejoras': 'Ventas más rápidas'},
      ],
      'v1.1.6': [
        {'Caracteristicas': 'Aviso de nueva versión'},
      ],
    },
  });

  group('ReleaseInfo.getChangelogSince', () {
    test('incluye todas las versiones intermedias más nuevas, de nueva a antigua',
        () {
      final sections = release.getChangelogSince('1.1.6', compareVersions);

      expect(sections.map((s) => s.version).toList(), ['1.1.8', '1.1.7']);
      expect(sections.first.entries, hasLength(1));
      expect(sections[1].entries, hasLength(2));
    });

    test('estando varias versiones atrasado acumula todos los cambios', () {
      final sections = release.getChangelogSince('1.1.5', compareVersions);

      expect(sections.map((s) => s.version).toList(), ['1.1.8', '1.1.7', '1.1.6']);
      final totalEntries =
          sections.fold<int>(0, (sum, s) => sum + s.entries.length);
      expect(totalEntries, 4);
    });

    test('acepta la versión actual con o sin prefijo v', () {
      final sections = release.getChangelogSince('v1.1.7', compareVersions);

      expect(sections.map((s) => s.version).toList(), ['1.1.8']);
    });

    test('sin versiones más nuevas devuelve lista vacía', () {
      expect(release.getChangelogSince('1.1.8', compareVersions), isEmpty);
    });

    test('omite versiones sin entradas de changelog', () {
      final conVacia = ReleaseInfo.fromJson({
        'version': '2.0.0',
        'apks': <String, dynamic>{},
        'changelog': {
          'v2.0.0': [
            {'Mejoras': 'Algo nuevo'},
          ],
          'v1.9.0': <dynamic>[],
        },
      });

      final sections = conVacia.getChangelogSince('1.8.0', compareVersions);
      expect(sections.map((s) => s.version).toList(), ['2.0.0']);
    });
  });
}
