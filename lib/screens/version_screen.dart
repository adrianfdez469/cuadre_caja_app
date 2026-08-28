import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/app_snackbar.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/apk_install_helper.dart';
import '../core/utils/device_abi.dart';
import '../data/models/release_model.dart';
import '../providers/ventas_provider.dart';
import '../services/release_service.dart' show ReleaseService, compareVersions;

class VersionScreen extends StatefulWidget {
  const VersionScreen({super.key});

  @override
  State<VersionScreen> createState() => _VersionScreenState();
}

class _VersionScreenState extends State<VersionScreen> {
  String _currentVersion = AppConstants.appVersion;
  String _currentBuildNumber = '';
  ReleaseInfo? _remoteRelease;
  bool _loading = false;
  bool _error = false;
  String? _errorMessage;
  bool _downloading = false;
  int _downloadProgress = 0;
  int _downloadTotal = 0;

  final ReleaseService _releaseService = ReleaseService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Cargar la versión actual primero: _hasUpdate la compara con la remota, así
    // que la comprobación automática debe correr después de tenerla. Siempre se
    // comprueba al abrir la pantalla, sin botón manual.
    await _loadPackageInfo();
    if (mounted) {
      await _checkUpdates();
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentVersion = info.version;
          _currentBuildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      // Mantener AppConstants.appVersion
    }
  }

  Future<void> _checkUpdates() async {
    if (AppConstants.driveReleasesJsonFileId.isEmpty) {
      setState(() {
        _error = true;
        _errorMessage = 'No está configurado el archivo de releases en Drive.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
      _errorMessage = null;
      _remoteRelease = null;
    });
    try {
      var release = await _releaseService.fetchReleases();
      if (release != null && AppConstants.driveRoadmapJsonFileId.isNotEmpty) {
        release = await _releaseService.fetchRoadmapAndMerge(release);
      }
      if (!mounted) return;
      setState(() {
        _remoteRelease = release;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _errorMessage = e.toString();
      });
    }
  }

  bool get _hasUpdate {
    if (_remoteRelease == null) return false;
    return compareVersions(_remoteRelease!.version, _currentVersion) > 0;
  }

  void _showDriveFolderFallback() {
    final url = AppConstants.driveFolderUrl;
    Clipboard.setData(ClipboardData(text: url));
    AppSnackBar.show(
      context,
      content: const Text(
        'No se pudo abrir el enlace. La URL se ha copiado al portapapeles; pégala en el navegador.',
      ),
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _startUpdate() async {
    final ventas = context.read<VentasProvider>();
    if (ventas.pendingCount > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ventas pendientes'),
          content: Text(
            'Tienes ${ventas.pendingCount} ventas sin sincronizar. '
            'Recomendamos sincronizar antes de actualizar. ¿Continuar con la actualización?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Actualizar igualmente'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    if (_remoteRelease == null) return;
    if (!Platform.isAndroid) {
      AppSnackBar.show(
        context,
        content: const Text(
            'La actualización automática solo está disponible en Android.'),
        backgroundColor: context.colors.caution,
      );
      return;
    }

    final abi = await getAndroidAbi();
    final fileId = _releaseService.getApkFileIdForDevice(_remoteRelease!, androidAbi: abi);
    if (fileId == null || fileId.isEmpty) {
      AppSnackBar.show(
        context,
        content: const Text('No hay APK disponible para este dispositivo.'),
        backgroundColor: context.colors.negative,
      );
      return;
    }

    setState(() => _downloading = true);
    try {
      final file = await _releaseService.downloadApk(
        fileId,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = received;
              _downloadTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _downloading = false);
      if (file == null) {
        AppSnackBar.show(
          context,
          content: const Text(
            'Error al descargar el APK. Descárgalo manualmente desde la carpeta de Drive.',
          ),
          backgroundColor: context.colors.negative,
        );
        return;
      }

      final validation = await ApkInstallHelper.validateForUpdate(file.path);
      if (!mounted) return;

      if (validation != null && !validation.canInstall) {
        if (validation.reason == 'unknown_sources_blocked') {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Permiso necesario'),
              content: Text(validation.userMessage()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Abrir ajustes'),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            await ApkInstallHelper.openUnknownSourcesSettings();
          }
          return;
        }

        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No se puede instalar'),
            content: Text(validation.userMessage()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
        return;
      }

      final installed = await ApkInstallHelper.installApk(file.path);
      if (!installed && mounted) {
        AppSnackBar.show(
          context,
          content: const Text(
            'No se pudo abrir el instalador. Descarga el APK manualmente desde Drive.',
          ),
          backgroundColor: context.colors.caution,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        AppSnackBar.show(
          context,
          content: Text('Error: $e'),
          backgroundColor: context.colors.negative,
        );
      }
    }
  }

  /// Texto de estado de la comprobación de actualizaciones. Reemplaza al botón
  /// "Comprobar actualizaciones": la comprobación ahora es automática al abrir
  /// la pantalla, así que aquí solo se refleja su progreso/resultado.
  Widget _buildStatusText() {
    final colors = context.colors;
    late final IconData icon;
    late final Color color;
    late final String message;

    if (_loading) {
      color = colors.textSecondary;
      message = 'Comprobando actualizaciones...';
    } else if (_error) {
      icon = Icons.error_outline;
      color = colors.negative;
      message = _errorMessage ?? 'Error al conectar con Drive.';
    } else if (_hasUpdate) {
      icon = Icons.system_update;
      color = colors.info;
      message = 'Hay una actualización disponible.';
    } else if (_remoteRelease != null) {
      icon = Icons.check_circle_outline;
      color = colors.positive;
      message = 'Estás usando la última versión disponible.';
    } else {
      icon = Icons.info_outline;
      color = colors.textSecondary;
      message = 'Sin información de actualizaciones.';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ),
      ],
    );
  }

  /// Lista de bullets del changelog. Si el usuario está varias versiones
  /// atrasado, muestra los cambios de TODAS las versiones intermedias (de la más
  /// nueva a la más antigua), cada una bajo su encabezado de versión. Si solo hay
  /// una versión nueva, muestra los bullets sin encabezado (el título de la
  /// tarjeta ya indica la versión).
  List<Widget> _buildChangelogSections() {
    final release = _remoteRelease;
    if (release == null) return const [];

    final sections = release.getChangelogSince(_currentVersion, compareVersions);
    // Respaldo: si el mapa de changelog no trae versiones intermedias, cae a las
    // entradas de la última versión disponible.
    if (sections.isEmpty) {
      return release
          .getChangelogEntries(release.version)
          .map(_buildChangelogBullet)
          .toList();
    }

    final showVersionHeaders = sections.length > 1;
    final widgets = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      if (showVersionHeaders) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 12, bottom: 6),
          child: Text(
            'v${section.version}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: context.colors.info,
            ),
          ),
        ));
      }
      widgets.addAll(section.entries.map(_buildChangelogBullet));
    }
    return widgets;
  }

  Widget _buildChangelogBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Versión'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Versión actual',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentBuildNumber.isNotEmpty
                        ? 'v$_currentVersion (build $_currentBuildNumber)'
                        : 'v$_currentVersion',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (AppConstants.driveReleasesJsonFileId.isEmpty)
            Card(
              color: colors.cautionWash,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Para comprobar actualizaciones, configura el ID del archivo releases.json en la carpeta de Drive (constante driveReleasesJsonFileId).',
                ),
              ),
            )
          else ...[
            _buildStatusText(),
            if (_hasUpdate) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                color: colors.infoWash,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.system_update, color: colors.info, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Hay una actualización disponible: v${_remoteRelease!.version}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._buildChangelogSections(),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _downloading ? null : _startUpdate,
                          icon: _downloading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: _downloadTotal > 0
                                        ? _downloadProgress / _downloadTotal
                                        : null,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(
                            _downloading
                                ? (_downloadTotal > 0
                                    ? 'Descargando ${(_downloadProgress / 1024).toStringAsFixed(0)} / ${(_downloadTotal / 1024).toStringAsFixed(0)} KB'
                                    : 'Descargando...')
                                : 'Actualizar aplicación',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(AppConstants.driveFolderUrl);
              try {
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && mounted) {
                  _showDriveFolderFallback();
                }
              } catch (_) {
                if (mounted) _showDriveFolderFallback();
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Ver carpeta de releases en Drive'),
          ),
          const SizedBox(height: 8),
          SelectableText(
            AppConstants.driveFolderUrl,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
