import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.cuadre_caja_app/native');

/// Obtiene la ABI principal del dispositivo (solo Android).
/// Devuelve por ejemplo: arm64-v8a, armeabi-v7a, x86_64.
Future<String?> getAndroidAbi() async {
  if (!Platform.isAndroid) return null;
  try {
    final abi = await _channel.invokeMethod<String>('getAndroidAbi');
    return abi;
  } catch (_) {
    return null;
  }
}
