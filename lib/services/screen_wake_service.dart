import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Mantiene la pantalla encendida mientras hay una venta en curso.
///
/// El cajero deja el dispositivo en el mostrador con productos ya cargados y
/// vuelve a él cuando el cliente termina de decidir; que se apague a mitad
/// obliga a desbloquear con las manos ocupadas.
///
/// Se activa solo con una venta empezada, no durante todo el período: en los
/// ratos muertos la pantalla vuelve a apagarse sola y no se come la batería de
/// un dispositivo que puede no estar enchufado.
///
/// Todas las llamadas van bajo `try/catch`, igual que [ScanFeedbackService]: en
/// widget tests el plugin no está registrado y lanzaría `MissingPluginException`,
/// y que la pantalla se apague nunca puede tumbar el POS.
class ScreenWakeService {
  ScreenWakeService._();

  static final ScreenWakeService instance = ScreenWakeService._();

  /// Último estado pedido, para no llamar al plugin en cada notificación del
  /// carrito (que llega en cada cambio de cantidad).
  bool _activo = false;

  /// [activo] = hay una venta en curso.
  Future<void> setActivo(bool activo) async {
    if (_activo == activo) return;
    _activo = activo;
    try {
      await WakelockPlus.toggle(enable: activo);
    } catch (e) {
      logDebug('⚠️ No se pudo cambiar el wakelock: $e');
    }
  }

  /// Libera la pantalla pase lo que pase. Para `dispose()`: salir del POS o
  /// cerrar sesión no debe dejar el wakelock colgado.
  Future<void> liberar() => setActivo(false);
}
