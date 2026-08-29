import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';

/// Botón principal de cobro, compartido por la barra de la pantalla de venta y
/// por el pie de la vista ampliada de la cuenta, que antes lo dibujaban cada
/// una con tamaños y pesos distintos.
///
/// "Cobrar" es la acción y va en negrita; "N artículos" es el dato que la
/// acompaña, así que va más fino y más claro para no competir con ella.
class CobrarButton extends StatelessWidget {
  const CobrarButton({
    super.key,
    required this.unidades,
    required this.onPressed,
  });

  /// Unidades reales del carrito (no líneas): 3 × un producto son 3 artículos.
  final double unidades;

  /// `null` deshabilita el botón (carrito vacío).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final habilitado = onPressed != null;

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        disabledBackgroundColor: colors.onInverseMuted.withValues(alpha: 0.3),
        minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Text(
            'Cobrar',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (habilitado) ...[
            const SizedBox(width: 8),
            Text(
              Formatters.formatUnidades(unidades),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: colors.onAccent.withValues(alpha: 0.65),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
