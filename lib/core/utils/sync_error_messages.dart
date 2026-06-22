/// Utilidad para mostrar mensajes amigables al usuario según las respuestas
/// documentadas en API_APP_VENTA_POST_RESPUESTAS.md cuando una venta no se sincroniza.
class SyncErrorMessages {
  SyncErrorMessages._();

  /// Devuelve un título corto para el error, según el contenido del mensaje del API.
  static String title(String? rawMessage) {
    if (rawMessage == null || rawMessage.isEmpty) {
      return 'Error al sincronizar';
    }
    final m = rawMessage.toLowerCase();
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
