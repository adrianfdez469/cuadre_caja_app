import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../data/models/venta_model.dart';

/// Cómo se nombra y se colorea cada [SyncState] en la interfaz.
///
/// Vive fuera del widget porque el texto se necesita también suelto: en las
/// etiquetas de accesibilidad y en los contadores de los filtros.
///
/// El criterio de tono es el mismo que fija `BadgeTone` en [sync_badge.dart]:
/// rojo es "falló, hay que mirarlo", ámbar es "sólo espera conexión" e `info`
/// es "se está moviendo ahora mismo".
class SyncStateLabels {
  const SyncStateLabels._();

  static String label(SyncState s) => switch (s) {
    SyncState.synced => 'Sincronizada',
    SyncState.syncing => 'Sincronizando',
    SyncState.pending => 'Pendiente',
    SyncState.error => 'Error',
    SyncState.cancelPending => 'Anulación pendiente',
    SyncState.cancelling => 'Anulando',
    SyncState.cancelError => 'Anulación fallida',
  };

  static Color ink(SyncState s, AppSemanticColors c) => switch (s) {
    SyncState.synced => c.positive,
    SyncState.syncing => c.info,
    SyncState.pending => c.caution,
    SyncState.error => c.negative,
    SyncState.cancelPending => c.caution,
    SyncState.cancelling => c.info,
    SyncState.cancelError => c.negative,
  };

  /// Fondo del chip. Son los tokens `*Wash` del sistema, no un alpha calculado
  /// sobre [ink]: el wash está pensado para el fondo de cada tono y se define
  /// aparte en claro y en oscuro.
  static Color wash(SyncState s, AppSemanticColors c) => switch (s) {
    SyncState.synced => c.positiveWash,
    SyncState.syncing => c.infoWash,
    SyncState.pending => c.cautionWash,
    SyncState.error => c.negativeWash,
    SyncState.cancelPending => c.cautionWash,
    SyncState.cancelling => c.infoWash,
    SyncState.cancelError => c.negativeWash,
  };

  /// Icono para los sitios donde el chip no cabe y hay que resumirlo.
  static IconData icon(SyncState s) => switch (s) {
    SyncState.synced => Icons.cloud_done_outlined,
    SyncState.syncing => Icons.cloud_sync_outlined,
    SyncState.pending => Icons.cloud_queue,
    SyncState.error => Icons.cloud_off_outlined,
    SyncState.cancelPending => Icons.remove_circle_outline,
    SyncState.cancelling => Icons.remove_circle_outline,
    SyncState.cancelError => Icons.report_gmailerrorred_outlined,
  };
}

/// Píldora con el estado de sincronización de una venta.
///
/// Cubre **los siete** [SyncState]. Antes cada pantalla tenía el suyo: la lista
/// de ventas los pintaba todos con chips de texto y la de productos vendidos
/// sólo cuatro con iconos de nube, de modo que una anulación pendiente aparecía
/// ahí como "Sincronizando".
class SyncStateChip extends StatelessWidget {
  final SyncState state;

  /// Añade el icono del estado delante del texto. Para listas donde el color
  /// solo no basta (fila apretada, mucho contenido alrededor).
  final bool showIcon;

  const SyncStateChip(this.state, {super.key, this.showIcon = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = SyncStateLabels.ink(state, colors);
    final texto = SyncStateLabels.label(state);

    return Semantics(
      label: texto,
      container: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: SyncStateLabels.wash(state, colors),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: ink.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              Icon(SyncStateLabels.icon(state), size: 13, color: ink),
              const SizedBox(width: 4),
            ],
            // "Anulación pendiente" no cabe junto a la hora en un teléfono
            // con la letra ampliada. Se encoge antes que truncarse: media
            // etiqueta de estado no dice nada.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  texto,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
