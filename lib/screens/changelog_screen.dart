import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../data/models/release_model.dart';
import '../services/release_service.dart' show ReleaseService, compareVersions;

/// Historial completo de novedades: qué trae la versión instalada y qué traían
/// las anteriores. Se abre desde la pantalla "Versión".
///
/// El contenido sale de releases.json (el mismo archivo que usa el actualizador),
/// así que las versiones futuras aparecen aquí sin tocar la app. Si no hay red se
/// usa la última copia guardada en el equipo: el historial es justo lo que un
/// cajero sin conexión querrá consultar.
class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({
    super.key,
    required this.currentVersion,
    this.release,
    this.releaseService,
  });

  /// Versión instalada, para marcarla en la lista.
  final String currentVersion;

  /// Datos ya descargados por la pantalla de versión. Si vienen null se cargan
  /// aquí (red primero, caché después).
  final ReleaseInfo? release;

  /// Inyectable para los tests; en la app se construye uno propio.
  final ReleaseService? releaseService;

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  late final ReleaseService _releaseService =
      widget.releaseService ?? ReleaseService();

  ReleaseInfo? _release;
  bool _loading = false;

  /// Los datos vienen de la copia guardada en el equipo, no de Drive.
  bool _desdeCache = false;

  @override
  void initState() {
    super.initState();
    _release = widget.release;
    if (_release == null) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final remoto = await _releaseService.fetchReleases();
    if (!mounted) return;
    if (remoto != null) {
      setState(() {
        _release = remoto;
        _desdeCache = false;
        _loading = false;
      });
      return;
    }
    final cache = await _releaseService.loadCachedReleases();
    if (!mounted) return;
    setState(() {
      _release = cache;
      _desdeCache = cache != null;
      _loading = false;
    });
  }

  /// Color del tono semántico que le toca a cada categoría del changelog.
  Color _colorCategoria(String categoria, AppSemanticColors colors) {
    switch (categoria.toLowerCase()) {
      case 'arreglos':
        return colors.positive;
      case 'caracteristicas':
      case 'características':
        return colors.accent;
      case 'mejoras':
        return colors.info;
      default:
        return colors.neutral;
    }
  }

  IconData _iconoCategoria(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'arreglos':
        return Icons.build_outlined;
      case 'caracteristicas':
      case 'características':
        return Icons.auto_awesome_outlined;
      case 'mejoras':
        return Icons.trending_up;
      default:
        return Icons.circle;
    }
  }

  Widget _buildItem(ChangelogItem item, AppSemanticColors colors) {
    final color = _colorCategoria(item.categoria, colors);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_iconoCategoria(item.categoria), size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.categoria,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(item.texto, style: const TextStyle(fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersion(VersionChangelog section, AppSemanticColors colors) {
    final esActual = compareVersions(section.version, widget.currentVersion) == 0;
    final esFutura = compareVersions(section.version, widget.currentVersion) > 0;
    return Card(
      color: esActual ? colors.accentWash : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'v${section.version}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (esActual)
                  _Etiqueta(
                    texto: 'Tu versión',
                    color: colors.accent,
                    fondo: colors.raised,
                  )
                else if (esFutura)
                  _Etiqueta(
                    texto: 'Disponible',
                    color: colors.info,
                    fondo: colors.infoWash,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...section.items.map((i) => _buildItem(i, colors)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final release = _release;
    final secciones = release?.getAllChangelog(compareVersions) ?? const [];

    late final Widget cuerpo;
    if (_loading) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (secciones.isEmpty) {
      cuerpo = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 40, color: colors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'Todavía no hay historial de novedades guardado. Conéctate a '
                'internet para descargarlo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    } else {
      cuerpo = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_desdeCache)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: colors.caution),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sin conexión: se muestra el historial guardado en el equipo.',
                      style: TextStyle(fontSize: 12, color: colors.caution),
                    ),
                  ),
                ],
              ),
            ),
          ...secciones.map((s) => _buildVersion(s, colors)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Novedades')),
      body: cuerpo,
    );
  }
}

/// Etiqueta pequeña junto al número de versión ("Tu versión", "Disponible").
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({
    required this.texto,
    required this.color,
    required this.fondo,
  });

  final String texto;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
