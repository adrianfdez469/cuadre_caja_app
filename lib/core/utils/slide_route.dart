import 'package:flutter/material.dart';

/// Ruta que entra desde el borde derecho, como un panel que se desliza sobre la
/// pantalla actual. La usan el detalle de la cuenta y el cobro, que se sienten
/// como capas del mismo flujo y no como pantallas nuevas.
PageRouteBuilder<T> slideFromRightRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      );
    },
  );
}
