import 'dart:async';
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
  const VersionScreen({super.key, this.releaseService});

  /// Inyectable para los tests; en la app se construye uno propio.
  final ReleaseService? releaseService;

  @override
  State<VersionScreen> createState() => _VersionScreenState();
}

class _VersionScreenState extends State<VersionScreen>
    with WidgetsBindingObserver {
  String _currentVersion = AppConstants.appVersion;
  String _currentBuildNumber = '';
  ReleaseInfo? _remoteRelease;
  bool _loading = false;
  bool _error = false;
  String? _errorMessage;
  bool _downloading = false;
  int _downloadProgress = 0;
  int _downloadTotal = 0;

  /// APK ya descargado y válido para la versión remota. Mientras no sea null la
  /// pantalla ofrece instalar en vez de descargar, incluso después de cerrar y
  /// reabrir la app: el archivo en disco es la única fuente de verdad.
  File? _downloadedApk;
  String? _apkVariantKey;
  String? _apkFileId;

  /// Se mandó al usuario a Ajustes a conceder "instalar apps desconocidas". Al
  /// volver, el resume reanuda la instalación con el APK que ya está en disco.
  bool _awaitingPermission = false;

  /// Se lanzó el instalador del sistema. Si volvemos de él seguimos vivos, así
  /// que el usuario lo canceló.
  bool _installing = false;

  /// Evita que varios resumes encadenados disparen instalaciones en paralelo.
  bool _resumeBusy = false;

  late final ReleaseService _releaseService =
      widget.releaseService ?? ReleaseService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    // Cargar la versión actual primero: _hasUpdate la compara con la remota, así
    // que la comprobación automática debe correr después de tenerla. Siempre se
    // comprueba al abrir la pantalla, sin botón manual.
    await _loadPackageInfo();
    if (!mounted) return;
    await _checkUpdates();
    if (!mounted) return;
    await _syncLocalApk();
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

  /// Resuelve la variante de APK que toca a este dispositivo, busca si ya hay
  /// una descarga válida en disco y barre las obsoletas. Es idempotente: se
  /// llama al abrir la pantalla y cada vez que el estado local puede haber
  /// cambiado.
  Future<void> _syncLocalApk() async {
    if (!ApkInstallHelper.isAndroid) return;
    final release = _remoteRelease;
    // Sin releases.json no sabemos qué APK conservar, así que no se borra nada.
    if (_error || release == null) return;

    if (!_hasUpdate) {
      await _releaseService.cleanupApks();
      if (!mounted) return;
      setState(() => _downloadedApk = null);
      return;
    }

    final abi = await getAndroidAbi();
    final variantKey =
        _releaseService.getApkVariantKeyForDevice(release, androidAbi: abi);
    final fileId = variantKey == null ? null : release.apks[variantKey];
    if (variantKey == null || fileId == null || fileId.isEmpty) {
      await _releaseService.cleanupApks();
      return;
    }

    final file = await _releaseService.findDownloadedApk(
      version: release.version,
      variantKey: variantKey,
    );
    await _releaseService.cleanupApks(
      keepFileName: ReleaseService.apkFileNameFor(
        version: release.version,
        variantKey: variantKey,
      ),
    );
    if (!mounted) return;
    setState(() {
      _apkVariantKey = variantKey;
      _apkFileId = fileId;
      _downloadedApk = file;
    });
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

    final release = _remoteRelease;
    if (release == null) return;
    if (!ApkInstallHelper.isAndroid) {
      AppSnackBar.show(
        context,
        content: const Text(
            'La actualización automática solo está disponible en Android.'),
        backgroundColor: context.colors.caution,
      );
      return;
    }

    // Si ya está descargado no se vuelve a bajar: es justo el caso del usuario
    // que acaba de conceder el permiso de instalación.
    if (_downloadedApk != null) {
      await _installDownloadedApk();
      return;
    }

    var variantKey = _apkVariantKey;
    var fileId = _apkFileId;
    if (variantKey == null || fileId == null || fileId.isEmpty) {
      final abi = await getAndroidAbi();
      variantKey =
          _releaseService.getApkVariantKeyForDevice(release, androidAbi: abi);
      fileId = variantKey == null ? null : release.apks[variantKey];
      if (!mounted) return;
    }
    if (variantKey == null || fileId == null || fileId.isEmpty) {
      AppSnackBar.show(
        context,
        content: const Text('No hay APK disponible para este dispositivo.'),
        backgroundColor: context.colors.negative,
      );
      return;
    }

    setState(() {
      _apkVariantKey = variantKey;
      _apkFileId = fileId;
      _downloading = true;
      _downloadProgress = 0;
      _downloadTotal = 0;
    });
    try {
      final file = await _releaseService.downloadApk(
        fileId,
        version: release.version,
        variantKey: variantKey,
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
      setState(() {
        _downloading = false;
        _downloadedApk = file;
      });
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
      await _installDownloadedApk();
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

  /// Punto único de entrada a la instalación: lo usan el botón, el final de la
  /// descarga y la reanudación tras conceder el permiso. Siempre revalida el
  /// archivo, porque entre que se descargó y ahora el sistema o el usuario han
  /// podido borrarlo.
  Future<void> _installDownloadedApk() async {
    final file = _downloadedApk;
    if (file == null) return;
    if (!file.existsSync() || !ReleaseService.looksLikeApk(file)) {
      setState(() {
        _downloadedApk = null;
        _awaitingPermission = false;
        _installing = false;
      });
      AppSnackBar.show(
        context,
        content: const Text(
          'El archivo descargado ya no está disponible. Vuelve a descargarlo.',
        ),
        backgroundColor: context.colors.caution,
      );
      return;
    }

    final validation = await ApkInstallHelper.validateForUpdate(file.path);
    if (!mounted) return;
    if (validation != null && !validation.canInstall) {
      await _handleValidationFailure(validation, file);
      return;
    }

    setState(() => _installing = true);
    final installed = await ApkInstallHelper.installApk(file.path);
    if (!mounted) return;
    if (installed) return;

    // MainActivity.installApk devuelve false y abre Ajustes por su cuenta
    // cuando falta el permiso, sin avisar a Dart: hay que preguntarlo.
    final granted = await ApkInstallHelper.canInstallFromUnknownSources();
    if (!mounted) return;
    setState(() {
      _installing = false;
      _awaitingPermission = !granted;
    });
    if (granted) {
      AppSnackBar.show(
        context,
        content: const Text(
          'No se pudo abrir el instalador. Descarga el APK manualmente desde Drive.',
        ),
        backgroundColor: context.colors.caution,
      );
    }
  }

  Future<void> _handleValidationFailure(
    ApkUpdateValidation validation,
    File file,
  ) async {
    if (validation.reason == 'unknown_sources_blocked') {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permiso necesario'),
          content: Text(
            '${validation.userMessage()}\n\n'
            'El APK ya está descargado: al volver a esta pantalla la instalación '
            'continuará sola, sin descargarlo otra vez.',
          ),
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
      if (!mounted) return;
      if (openSettings == true) {
        // El APK se conserva a propósito: es lo que permite reanudar al volver.
        setState(() => _awaitingPermission = true);
        await ApkInstallHelper.openUnknownSourcesSettings();
      }
      return;
    }

    // El resto de motivos (APK corrupto, de otra app o de una versión anterior)
    // no se arreglan reintentando: se borra para no dejar decenas de MB ocupados.
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    setState(() {
      _downloadedApk = null;
      _awaitingPermission = false;
      _installing = false;
    });
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_resumeBusy || _downloading) return;
    // Un resume cualquiera (volver de otra app) no debe disparar nada.
    if (!_awaitingPermission && !_installing) return;
    _resumeBusy = true;
    unawaited(_onAppResumed().whenComplete(() => _resumeBusy = false));
  }

  Future<void> _onAppResumed() async {
    if (_awaitingPermission) {
      final granted = await ApkInstallHelper.canInstallFromUnknownSources();
      if (!mounted) return;
      if (!granted) return; // sigue sin concederlo: esperamos en silencio
      setState(() => _awaitingPermission = false);
      await _installDownloadedApk();
      return;
    }
    // Si la instalación hubiera arrancado, este proceso estaría muerto: llegar
    // aquí significa que el usuario canceló el instalador del sistema.
    if (mounted) setState(() => _installing = false);
  }

  /// Botón de la tarjeta de actualización. Un solo botón con cinco estados:
  /// descargable, descargando, listo para instalar, esperando permiso e
  /// instalando. Cuando el APK ya está en disco no vuelve a descargar.
  Widget _buildUpdateButton() {
    final busy = _downloading || _installing;
    final ready = _downloadedApk != null;

    Widget icon;
    String label;
    if (_downloading) {
      icon = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: _downloadTotal > 0 ? _downloadProgress / _downloadTotal : null,
        ),
      );
      label = _downloadTotal > 0
          ? 'Descargando ${(_downloadProgress / 1024).toStringAsFixed(0)} / ${(_downloadTotal / 1024).toStringAsFixed(0)} KB'
          : 'Descargando...';
    } else if (_installing) {
      icon = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      label = 'Abriendo instalador...';
    } else if (ready) {
      icon = const Icon(Icons.install_mobile);
      label = 'Instalar ahora';
    } else {
      icon = const Icon(Icons.download);
      label = 'Actualizar aplicación';
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : _startUpdate,
        icon: icon,
        label: Text(label),
      ),
    );
  }

  /// Aclara por qué el botón dice "Instalar ahora" y qué pasa al volver de los
  /// ajustes de permisos.
  List<Widget> _buildUpdateHint() {
    if (_downloading || _installing || _downloadedApk == null) return const [];
    final colors = context.colors;
    final text = _awaitingPermission
        ? 'Concede el permiso en Ajustes y vuelve a esta pantalla: la instalación continuará automáticamente.'
        : 'El APK de la v${_remoteRelease!.version} ya está descargado; no hace falta volver a descargarlo.';
    return [
      const SizedBox(height: 8),
      Text(text, style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
    ];
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
            style: TextStyle(color: color, fontSize: 13),
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
                      fontSize: 11.5,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentBuildNumber.isNotEmpty
                        ? 'v$_currentVersion (build $_currentBuildNumber)'
                        : 'v$_currentVersion',
                    style: const TextStyle(
                      fontSize: 22,
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
                                fontSize: 17,
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
                      _buildUpdateButton(),
                      ..._buildUpdateHint(),
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
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
