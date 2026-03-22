import 'package:flutter/material.dart';

/// SnackBar unificado: icono de cierre y swipe horizontal para descartar.
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: behavior,
        showCloseIcon: true,
        closeIconColor: _closeIconColor(context, backgroundColor),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }
}
