import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Tono de una métrica, con el significado que fija `AppSemanticColors`.
///
/// Se declara el tono, no el color: las tarjetas que esto sustituye calculaban
/// sus fondos con `withValues(alpha: 0.08 / 0.12 / 0.3)` sobre el color de
/// texto, lo que dejaba el propio texto por debajo del contraste mínimo. Aquí
/// el fondo es el token `*Wash` y el texto el `ink` a plena opacidad.
enum StatTone { accent, positive, negative, caution, info, neutral }

extension StatToneColors on StatTone {
  Color ink(AppSemanticColors c) => switch (this) {
    StatTone.accent => c.accent,
    StatTone.positive => c.positive,
    StatTone.negative => c.negative,
    StatTone.caution => c.caution,
    StatTone.info => c.info,
    StatTone.neutral => c.neutral,
  };

  Color wash(AppSemanticColors c) => switch (this) {
    StatTone.accent => c.accentWash,
    StatTone.positive => c.positiveWash,
    StatTone.negative => c.negativeWash,
    StatTone.caution => c.cautionWash,
    StatTone.info => c.infoWash,
    StatTone.neutral => c.neutralWash,
  };
}

/// Una cifra con su rótulo, sobre el wash de su tono.
///
/// Sirve tanto para la fila de totales de una pantalla (con [icon] y
/// [centered]) como para las cajas de una tarjeta de producto (sin icono,
/// alineadas a la izquierda).
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final StatTone tone;
  final IconData? icon;
  final bool centered;

  /// La cifra en `titleLarge` en vez de `titleMedium`, para la métrica
  /// principal de un grupo.
  final bool emphasize;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.tone = StatTone.neutral,
    this.icon,
    this.centered = false,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final ink = tone.ink(colors);

    return Semantics(
      label: '$label: $value',
      container: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: tone.wash(colors),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: ink.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: ink),
              const SizedBox(height: 4),
            ],
            Text(
              label,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: text.bodySmall!.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: centered ? Alignment.center : Alignment.centerLeft,
              child: Text(
                value,
                style: tabularNums(
                  (emphasize ? text.titleLarge! : text.titleMedium!).copyWith(
                    color: ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
