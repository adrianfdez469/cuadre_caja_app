import '../../data/models/venta_model.dart';

/// Qué hay que hacer para anular una venta.
enum AnulacionPlan {
  /// No hay fila en `ventas_pendientes`: la venta se hizo en otro dispositivo o
  /// por otro cajero. No se puede anular desde aquí — falta el detalle con el
  /// que restaurar el stock y el sitio donde guardar el estado de la anulación.
  sinFilaLocal,

  /// La venta nunca llegó al servidor (`serverId == null`): basta con borrarla
  /// localmente y devolver el stock. Funciona igual con y sin conexión.
  borradoLocal,

  /// La venta existe en el servidor: la anulación se encola y solo se da por
  /// buena cuando el servidor la confirma.
  encolar,

  /// Ya hay una anulación pedida sobre esta venta (pendiente, en vuelo o
  /// fallida). No se vuelve a pedir.
  yaEnCurso,

  /// El POST de la venta está en vuelo: todavía no se sabe si el servidor la
  /// va a aceptar ni con qué `serverId`. Borrarla ahora dejaría una venta
  /// huérfana en el servidor que este dispositivo ya no sabría anular.
  subidaEnVuelo,
}

/// Cómo terminó una petición de anulación.
enum AnulacionResultado {
  /// La venta se borró en el acto (nunca llegó al servidor).
  borrada,

  /// La anulación quedó en cola. Con conexión el drenaje ya arrancó en segundo
  /// plano; sin conexión se aplicará al reconectar.
  encolada,

  /// No hay fila local: no se puede anular desde este dispositivo.
  noPermitida,

  /// Ya había una anulación pedida sobre esta venta.
  yaEnCurso,

  /// La venta se está subiendo justo ahora: hay que esperar a que termine.
  subidaEnVuelo,
}

/// Decide cómo anular una venta, a partir únicamente del estado de su fila
/// local. Función pura y sin dependencias de red o BD para poder testearla
/// aislada, en la línea de `producto_pos_rules.dart` y `payment_logic.dart`.
///
/// El discriminador es **`serverId`**, no `syncState`: `serverId` solo se
/// escribe tras un POST exitoso, así que es la única señal fiable de que la
/// venta existe del otro lado. Una venta en `error` que nunca obtuvo `serverId`
/// puede borrarse sin hablar con el servidor.
class VentaCancelPolicy {
  const VentaCancelPolicy._();

  static AnulacionPlan planFor(VentaLocalModel? venta) {
    if (venta == null) return AnulacionPlan.sinFilaLocal;
    if (venta.syncState.esAnulacion) return AnulacionPlan.yaEnCurso;
    if (venta.syncState == SyncState.syncing) {
      return AnulacionPlan.subidaEnVuelo;
    }
    if (venta.serverId == null || venta.serverId!.isEmpty) {
      return AnulacionPlan.borradoLocal;
    }
    return AnulacionPlan.encolar;
  }

  /// ¿La anulación se resolverá sola en este momento, o quedará esperando?
  ///
  /// Solo tiene sentido para [AnulacionPlan.encolar]: el borrado local es
  /// siempre inmediato.
  static bool quedaPendiente(AnulacionPlan plan, {required bool isOnline}) =>
      plan == AnulacionPlan.encolar && !isOnline;
}
