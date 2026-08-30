import 'package:flutter/material.dart';

/// SnackBar unificado: icono de cierre y swipe horizontal para descartar.
///
/// Siempre muestra **solo el mensaje más reciente**. Por defecto
/// `ScaffoldMessenger` encola los SnackBars y los va mostrando de uno en uno
/// esperando la `duration` de cada uno; al escanear con pistola o encadenar
/// acciones rápidas se acumulaba un atasco de mensajes viejos que seguían
/// apareciendo mucho después de la acción que los provocó. `clearSnackBars`
/// descarta la cola pendiente y anima la salida del actual, así que el mensaje
/// nuevo entra de inmediato sin cortes bruscos.
class AppSnackBar {
  AppSnackBar._();

  static Color _closeIconColor(BuildContext context, Color? backgroundColor) {
    if (backgroundColor != null) {
      return ThemeData.estimateBrightnessForColor(backgroundColor) ==
              Brightness.light
          ? Colors.black87
          : Colors.white;
    }
    return Theme.of(context).colorScheme.onInverseSurface;
  }

  static void show(
    BuildContext context, {
    required Widget content,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
    SnackBarBehavior behavior = SnackBarBehavior.floating,
  }) {
    showOn(
      ScaffoldMessenger.of(context),
      content: content,
      backgroundColor: backgroundColor,
      duration: duration,
      behavior: behavior,
      closeIconColor: _closeIconColor(context, backgroundColor),
    );
  }

  /// Igual que [show] pero con un messenger ya resuelto, para avisar después de
  /// un `await`: ahí el elemento puede estar desactivado y `ScaffoldMessenger.of`
  /// revienta aunque `mounted` siga en `true`.
  static void showOn(
    ScaffoldMessengerState messenger, {
    required Widget content,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    Color? closeIconColor,
  }) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: behavior,
        showCloseIcon: true,
        closeIconColor: closeIconColor,
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }
}
