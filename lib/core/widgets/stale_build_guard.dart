import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/apk_install_helper.dart';

/// Cubre toda la app cuando el proceso en ejecución dejó de corresponder al APK
/// instalado.
///
/// Android normalmente mata la app al reemplazar su APK, pero no siempre lo
/// hace: la ventana de la versión vieja puede seguir viva mientras el instalador
/// ofrece "Abrir", y entonces quedan dos versiones distintas de la app corriendo
/// a la vez sobre la misma base de datos SQLite. Al detectarlo se tapa la UI
/// vieja y se cierra el proceso, quitando además su tarjeta de "recientes" para
/// que nadie vuelva a entrar por ahí.
///
/// Va en el `builder` de MaterialApp (por encima del Navigator), así que cubre
/// también los diálogos y las rutas apiladas.
class StaleBuildGuard extends StatefulWidget {
  const StaleBuildGuard({super.key, required this.child});

  final Widget child;

  @override
  State<StaleBuildGuard> createState() => _StaleBuildGuardState();
}

class _StaleBuildGuardState extends State<StaleBuildGuard>
    with WidgetsBindingObserver {
  StaleBuildInfo? _stale;
  bool _checking = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // También al arrancar: la actividad puede recrearse (rotación, cambio de
    // tema) dentro de un proceso que ya quedó obsoleto.
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking || _stale != null) return;
    _checking = true;
    try {
      final info = await ApkInstallHelper.checkStaleBuild();
      if (!mounted || info == null || !info.stale) return;
      setState(() => _stale = info);
    } finally {
      _checking = false;
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    await ApkInstallHelper.closeApp();
  }

  @override
  Widget build(BuildContext context) {
    final stale = _stale;
    return Stack(
      children: [
        widget.child,
        if (stale != null)
          // El aviso se dibuja fuera del Navigator, así que necesita sus propios
          // Directionality/Material heredados de MaterialApp: los da el Scaffold.
          Positioned.fill(child: _StaleBuildNotice(info: stale, onClose: _close, closing: _closing)),
      ],
    );
  }
}

class _StaleBuildNotice extends StatelessWidget {
  const _StaleBuildNotice({
    required this.info,
    required this.onClose,
    required this.closing,
  });

  final StaleBuildInfo info;
  final VoidCallback onClose;
  final bool closing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final version = info.installedVersionName;
    return PopScope(
      // Volver atrás no sirve de nada aquí: la única salida es cerrar.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_alt, size: 56, color: colors.info),
                  const SizedBox(height: 16),
                  Text(
                    version != null && version.isNotEmpty
                        ? 'Se instaló la versión $version'
                        : 'Se instaló una versión nueva',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Esta ventana quedó con la versión anterior. Ciérrala y abre '
                    'la app desde el icono para seguir vendiendo con la versión nueva. '
                    'Tus ventas no se pierden: están guardadas en el equipo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: closing ? null : onClose,
                      icon: closing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close),
                      label: Text(closing ? 'Cerrando...' : 'Cerrar esta ventana'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
