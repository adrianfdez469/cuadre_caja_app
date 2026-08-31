import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Estado vacío de una pantalla: icono, qué pasa y —cuando hay— qué hacer.
///
/// Unifica las cuatro variantes que había sueltas (iconos de 40, 56 y 64, gaps
/// distintos y una sin icono siquiera). Las medidas son las de la pantalla de
/// novedades, que era la más completa.
///
/// El [action] importa tanto como el texto: un vacío causado por un filtro sin
/// forma de quitarlo es un callejón sin salida. Por eso quien lo use debe
/// distinguir "aquí no hay nada" de "tus filtros no dejan nada".
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.textDisabled),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium!.copyWith(color: colors.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(color: colors.textSecondary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
