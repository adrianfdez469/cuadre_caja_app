import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
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
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentVersion = info.version;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La actualización automática solo está disponible en Android.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final abi = await getAndroidAbi();
    final fileId = _releaseService.getApkFileIdForDevice(_remoteRelease!, androidAbi: abi);
    if (fileId == null || fileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay APK disponible para este dispositivo.'),
          backgroundColor: AppColors.error,
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al descargar el APK.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Versión'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
                  const Text(
                    'Versión actual',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v$_currentVersion',
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
              color: AppColors.warning.withOpacity(0.2),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Para comprobar actualizaciones, configura el ID del archivo releases.json en la carpeta de Drive (constante driveReleasesJsonFileId).',
                ),
              ),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _loading ? null : _checkUpdates,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_loading ? 'Comprobando...' : 'Comprobar actualizaciones'),
            ),
            if (_error) ...[
              const SizedBox(height: 12),
              Card(
                color: AppColors.error.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage ?? 'Error al conectar con Drive.',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ),
            ],
            if (_remoteRelease != null && !_hasUpdate && !_error) ...[
              const SizedBox(height: 12),
              Card(
                color: AppColors.success.withOpacity(0.1),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Estás usando la última versión disponible.'),
                ),
              ),
            ],
            if (_hasUpdate) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                color: AppColors.info.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.system_update, color: AppColors.info, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'Hay una actualización disponible: v${_remoteRelease!.version}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._remoteRelease!
                          .getChangelogEntries(_remoteRelease!.version)
                          .map((e) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Expanded(child: Text(e)),
                                  ],
                                ),
                              )),
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
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Ver carpeta de releases en Drive'),
          ),
          const SizedBox(height: 8),
          SelectableText(
            AppConstants.driveFolderUrl,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
