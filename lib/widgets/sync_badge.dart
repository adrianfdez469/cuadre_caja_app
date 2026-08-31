import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Tono de un badge de notificación. Sigue el significado fijado en
/// `AppSemanticColors`: rojo es "falló, hay que mirarlo", ámbar es "todavía no
/// es problema" y `accent` es un conteo neutro sin urgencia.
enum BadgeTone {
  /// El servidor rechazó algo (venta en `error`, anulación en `cancelError`).
  error,

  /// Sólo espera conexión (`pending`, `cancelPending`): se resuelve solo.
  pending,

  /// Conteo informativo, sin urgencia (cuentas abiertas).
  accent,
}

extension _BadgeToneColors on BadgeTone {
  Color ink(AppSemanticColors colors) => switch (this) {
        BadgeTone.error => colors.negative,
        BadgeTone.pending => colors.caution,
        BadgeTone.accent => colors.accent,
      };

  Color wash(AppSemanticColors colors) => switch (this) {
        BadgeTone.error => colors.negativeWash,
        BadgeTone.pending => colors.cautionWash,
        BadgeTone.accent => colors.accentWash,
      };
}

/// Píldora con un número, para el `trailing` de una fila de menú.
///
/// Con `count <= 0` no ocupa espacio: quien la usa puede pasarla siempre sin
/// tener que condicionarla.
class CountBadge extends StatelessWidget {
  final int count;
  final BadgeTone tone;

  /// Qué anuncia el lector de pantalla. Sin esto, un badge es sólo un número
  /// suelto sin contexto.
  final String? semanticsLabel;

  const CountBadge({
    super.key,
    required this.count,
    required this.tone,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final colors = context.colors;
    return Semantics(
      label: semanticsLabel,
      container: semanticsLabel != null,
      excludeSemantics: semanticsLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tone.wash(colors),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: tone.ink(colors),
          ),
        ),
      ),
    );
  }
}

/// Superpone un contador en la esquina de un icono o botón.
///
/// El rojo manda: si hay algo rechazado se pinta eso, aunque además haya cosas
/// esperando conexión. Sin nada que avisar devuelve el [child] intacto, sin
/// meter un `Stack` de más en el árbol.
class BadgedIcon extends StatelessWidget {
  final Widget child;
  final int errorCount;
  final int pendingCount;

  /// Qué anuncia el lector de pantalla sobre el badge. El [child] suele traer su
  /// propio `Tooltip`/`Semantics`, así que aquí sólo va el aviso.
  final String? semanticsLabel;

  const BadgedIcon({
    super.key,
    required this.child,
    this.errorCount = 0,
    this.pendingCount = 0,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hayError = errorCount > 0;
    final count = hayError ? errorCount : pendingCount;
    if (count <= 0) return child;

    final colors = context.colors;
    final tone = hayError ? BadgeTone.error : BadgeTone.pending;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2,
          right: -2,
          child: Semantics(
            label: semanticsLabel,
            container: semanticsLabel != null,
            excludeSemantics: semanticsLabel != null,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: tone.ink(colors),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                // Aro del color del fondo: sin él, el badge se confunde con el
                // relleno del botón sobre el que se apoya.
                border: Border.all(color: colors.raised, width: 2),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                  // El mismo cálculo que `AppSnackBar`: en oscuro los tonos
                  // semánticos son claros y el blanco fijo no se leería.
                  color: ThemeData.estimateBrightnessForColor(
                            tone.ink(colors),
                          ) ==
                          Brightness.light
                      ? Colors.black87
                      : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
