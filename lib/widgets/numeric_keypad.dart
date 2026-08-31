import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Teclado numérico propio (nunca el del sistema), compartido por las hojas
/// que piden un monto o cantidad tecleado a mano (cantidad de producto,
/// efectivo recibido en el cobro), según `pos-mobile-estados.html`/`cobro.html`.
class NumericKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;

  /// Etiqueta de la tecla inferior izquierda. Emite sus propios caracteres:
  /// `'00'`/`'000'` para montos grandes, `'.'` para cantidades con decimales.
  /// `null` la deja vacía y deshabilitada.
  final String? cornerLabel;

  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.cornerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget key(String label, {VoidCallback? onTap, bool enabled = true}) {
      // El '⌫' se dibuja como icono y sin etiqueta TalkBack lo leería como un
      // botón mudo; el resto de teclas ya se leen por su propio texto.
      final semantica = label == '⌫' ? 'Borrar' : label;

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Semantics(
            button: true,
            enabled: enabled,
            excludeSemantics: true,
            label: semantica,
            child: Material(
              color: colors.sunken,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                onTap: enabled ? onTap : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  height: AppTapTarget.comfortable,
                  child: Center(
                    child: label == '⌫'
                        ? Icon(
                            Icons.backspace_outlined,
                            color: colors.textPrimary,
                          )
                        : Text(
                            label,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: enabled
                                  ? colors.textPrimary
                                  : colors.textDisabled,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            key('1', onTap: () => onDigit('1')),
            key('2', onTap: () => onDigit('2')),
            key('3', onTap: () => onDigit('3')),
          ],
        ),
        Row(
          children: [
            key('4', onTap: () => onDigit('4')),
            key('5', onTap: () => onDigit('5')),
            key('6', onTap: () => onDigit('6')),
          ],
        ),
        Row(
          children: [
            key('7', onTap: () => onDigit('7')),
            key('8', onTap: () => onDigit('8')),
            key('9', onTap: () => onDigit('9')),
          ],
        ),
        Row(
          children: [
            key(
              cornerLabel ?? '',
              enabled: cornerLabel != null,
              onTap: cornerLabel == null
                  ? null
                  : () {
                      for (final c in cornerLabel!.split('')) {
                        onDigit(c);
                      }
                    },
            ),
            key('0', onTap: () => onDigit('0')),
            key('⌫', onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}
