/// Utilidad para mostrar mensajes amigables al usuario según las respuestas
/// documentadas en API_APP_VENTA_POST_RESPUESTAS.md cuando una venta no se sincroniza.
class SyncErrorMessages {
  SyncErrorMessages._();

  /// El negocio no tiene registrada una tasa que la venta necesita para
  /// convertir a moneda base. El servidor completa el snapshot que manda la app
  /// con las tasas del negocio antes de validar, así que llegar aquí significa
  /// que la tasa no existe en ninguna parte.
  static const String missingExchangeRate = 'MISSING_EXCHANGE_RATE';

  /// Códigos que no se arreglan reintentando: hace falta que alguien cambie
  /// algo en el backend (registrar una tasa, por ejemplo). Reintentarlos en
  /// cada reconexión sólo gasta batería y datos, y deja la venta en rojo sin
  /// que el mensaje cambie nunca.
  static const Set<String> codigosPermanentes = {missingExchangeRate};

  /// True si el error no se resuelve solo y hay que sacarlo de la cola de
  /// reintento automático.
  static bool isPermanent(String? code) =>
      code != null && codigosPermanentes.contains(code);

  /// Devuelve un título corto para el error, según el contenido del mensaje del API.
  ///
  /// [code] es el campo `code` de la respuesta cuando el API lo manda: se mira
  /// primero porque es estable, mientras que el texto puede cambiar.
  static String title(String? rawMessage, {String? code}) {
    if (code == missingExchangeRate) return 'Falta una tasa de cambio';
    if (rawMessage == null || rawMessage.isEmpty) {
      return 'Error al sincronizar';
    }
    final m = rawMessage.toLowerCase();
    if (m.contains('no hay tasa de cambio registrada')) {
      return 'Falta una tasa de cambio';
    }
    if (m.contains('no autenticado')) return 'No autenticado';
    if (m.contains('datos insuficientes')) return 'Datos insuficientes';
    if (m.contains('no existe un período abierto')) return 'No hay período abierto';
    if (m.contains('no existe un período con el id')) return 'Período no encontrado';
    if (m.contains('período cerrado o diferente')) return 'Período no es el actual';
    if (m.contains('productos no encontrados')) return 'Productos no encontrados';
    if (m.contains('cantidad decimal no permitida')) return 'Cantidad decimal no permitida';
    if (m.contains('unidades sueltas') && m.contains('caja')) return 'Límite de fracción superado';
    if (m.contains('existencia insuficiente para desagregar')) return 'Stock insuficiente para desagregar';
    if (m.contains('existencia insuficiente')) return 'Stock insuficiente';
    if (m.contains('error al crear la venta')) return 'Error del servidor';
    return 'Error al sincronizar';
  }

  /// Mensaje completo para mostrar en el log (el que devolvió el servidor).
  static String detail(String? rawMessage) {
    return rawMessage?.trim().isNotEmpty == true ? rawMessage! : 'No hay detalles del error.';
  }

  /// Retorna true si el servidor rechazó la venta por stock insuficiente.
  static bool isStockError(String? rawMessage) {
    if (rawMessage == null || rawMessage.isEmpty) return false;
    final m = rawMessage.toLowerCase();
    return m.contains('existencia insuficiente');
  }

  /// Retorna true si el servidor rechazó la venta por falta de una tasa de
  /// cambio. Se detecta por [code], que es lo estable; el texto sólo sirve de
  /// respaldo para una respuesta que no lo traiga.
  static bool isMissingExchangeRate(String? code, String? rawMessage) {
    if (code == missingExchangeRate) return true;
    if (rawMessage == null || rawMessage.isEmpty) return false;
    return rawMessage.toLowerCase().contains('no hay tasa de cambio registrada');
  }

  /// Retorna true si el error es un conflicto de período (período cerrado o cambiado).
  /// En ese caso la UI puede ofrecer la opción de mover la venta al período actual.
  static bool isPeriodConflict(String? rawMessage) {
    if (rawMessage == null || rawMessage.isEmpty) return false;
    final m = rawMessage.toLowerCase();
    return m.contains('período cerrado o diferente') ||
        m.contains('no existe un período abierto') ||
        m.contains('no existe un período con el id');
  }
}
