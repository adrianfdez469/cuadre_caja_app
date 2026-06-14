import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.cuadre_caja_app/native');

/// Resultado de validar un APK descargado antes de instalarlo.
class ApkUpdateValidation {
  final bool canInstall;
  final String? reason;
  final int? apkVersionCode;
  final int? installedVersionCode;
  final String? apkVersionName;

  const ApkUpdateValidation({
    required this.canInstall,
    this.reason,
    this.apkVersionCode,
    this.installedVersionCode,
    this.apkVersionName,
  });

  factory ApkUpdateValidation.fromMap(Map<dynamic, dynamic> map) {
    return ApkUpdateValidation(
      canInstall: map['canInstall'] as bool? ?? false,
      reason: map['reason'] as String?,
      apkVersionCode: (map['apkVersionCode'] as num?)?.toInt(),
      installedVersionCode: (map['installedVersionCode'] as num?)?.toInt(),
      apkVersionName: map['apkVersionName'] as String?,
    );
  }

  String userMessage() {
    switch (reason) {
      case 'version_downgrade':
        return 'El APK descargado tiene un código de compilación menor '
            '($apkVersionCode) que la app instalada ($installedVersionCode). '
            'Android no permite instalar versiones anteriores. '
            'Vuelve a generar el APK incrementando el número después del + '
            'en pubspec.yaml (ej. 1.0.10+10).';
      case 'invalid_apk':
        return 'El archivo descargado no es un APK válido. '
            'Puede que Drive haya devuelto una página de error. '
            'Descarga el APK manualmente desde la carpeta de Drive.';
      case 'package_mismatch':
        return 'El APK descargado no corresponde a esta aplicación.';
      case 'unknown_sources_blocked':
        return 'Permite instalar apps de orígenes desconocidos para Cuadre de Caja '
            'en Ajustes → Seguridad → Instalar apps desconocidas.';
      default:
        return reason ?? 'No se pudo validar el APK para instalar.';
    }
  }
}

class ApkInstallHelper {
  ApkInstallHelper._();

  /// Comprueba que el APK sea válido y que su versionCode sea mayor que el instalado.
  static Future<ApkUpdateValidation?> validateForUpdate(String apkPath) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'validateApkForUpdate',
        {'apkPath': apkPath},
      );
      if (result == null) return null;
      return ApkUpdateValidation.fromMap(result);
    } catch (_) {
      return null;
    }
  }

  /// Abre el instalador de Android con permisos correctos (FileProvider).
  static Future<bool> installApk(String apkPath) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'installApk',
        {'apkPath': apkPath},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Indica si el usuario debe habilitar instalación desde orígenes desconocidos.
  static Future<bool> canInstallFromUnknownSources() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('canInstallFromUnknownSources');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Abre la pantalla de Android para permitir instalar desde esta app.
  static Future<void> openUnknownSourcesSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openUnknownSourcesSettings');
    } catch (_) {}
  }
}
