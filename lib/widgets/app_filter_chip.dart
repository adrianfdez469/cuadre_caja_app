import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Chip de filtro multi-selección.
///
/// El chip seleccionado va relleno con `accent` y etiqueta `onAccent`: el
/// `accentWash` es casi blanco en el tema claro y dejaba la etiqueta (blanca
/// por el `secondaryLabelStyle` del tema) ilegible.
///
/// Estaba copiado igual en la lista de productos vendidos y en el detalle de
/// venta; vive aquí para que la regla de contraste se arregle en un solo sitio.
class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Contador que acompaña a la etiqueta ("Con error 2"). Con `null` no se
  /// pinta; con 0 tampoco, para que un filtro vacío no muestre "0".
  final int? count;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texto = (count != null && count! > 0) ? '$label  $count' : label;
    return FilterChip(
      label: Text(texto),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: colors.sunken,
      selectedColor: colors.accent,
      checkmarkColor: colors.onAccent,
      labelStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        color: selected ? colors.onAccent : colors.textPrimary,
      ),
    );
  }
}

/// Selector de una opción entre varias (vista, modo, orden). Mismo criterio de
/// contraste que [AppFilterChip]: seleccionado = relleno `accent` + `onAccent`.
class AppChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: colors.sunken,
      selectedColor: colors.accent,
      labelStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        color: selected ? colors.onAccent : colors.textPrimary,
      ),
    );
  }
}
