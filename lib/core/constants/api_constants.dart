import 'dart:io' show Platform;

/// Ambientes contra los que puede apuntar la app.
enum Ambiente { local, pruebas, produccion }

class ApiConstants {
  // ---------------------------------------------------------------------------
  // Ambiente (se elige en tiempo de compilación, no en runtime)
  //
  //   flutter run   --dart-define=ENV=local
  //   flutter run   --dart-define=ENV=pruebas
  //   flutter build apk --release --dart-define=ENV=produccion   (o sin nada)
  //
  // Si necesitas una URL puntual que no sea ninguna de las tres (por ejemplo el
  // backend local corriendo en tu máquina, visto desde un celular físico):
  //
  //   flutter run --dart-define=API_URL=http://192.168.1.20:3000/api/app
  //
  // API_URL manda por sobre ENV. Por defecto, sin ningún --dart-define, la app
  // compila contra producción: los builds de release no cambian de
  // comportamiento si nadie pasa nada.
  // ---------------------------------------------------------------------------
  /// Vacío = nadie pasó ENV.
  static const String _envName = String.fromEnvironment('ENV');
  static const String _apiUrlOverride = String.fromEnvironment('API_URL');

  static const String produccionUrl = 'https://cuadrecaja.ventario.cloud/api/app';

  /// Se deja vacía a propósito. El ambiente de pruebas es un deploy preview de
  /// Vercel y su URL lleva el hash del deploy, así que cambia cada vez que se
  /// despliega: una constante aquí quedaría obsoleta sin avisar y apuntaría a
  /// un backend viejo. Para probar contra pruebas se pasa la URL del preview
  /// del momento con `--dart-define=API_URL=<url>/api/app`.
  static const String pruebasUrl = '';

  /// El backend local se ve en una dirección distinta según dónde corre la app:
  /// el emulador de Android llega al host por 10.0.2.2, mientras que macOS lo
  /// ve como localhost. Para un dispositivo físico usa `--dart-define=API_URL`
  /// con la IP LAN de tu máquina.
  static String get localUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:3000/api/app' : 'http://localhost:3000/api/app';

  static Ambiente get ambiente {
    switch (_envName) {
      case 'local':
      case 'dev':
        return Ambiente.local;
      case 'pruebas':
      case 'staging':
      case 'test':
        return Ambiente.pruebas;
      case 'produccion':
      case 'prod':
        return Ambiente.produccion;
    }
    // Sin ENV: una API_URL puesta a mano que no sea la de producción cuenta
    // como ambiente de pruebas, para que el build igual se delate en pantalla.
    if (_apiUrlOverride.isNotEmpty && _apiUrlOverride != produccionUrl) {
      return Ambiente.pruebas;
    }
    return Ambiente.produccion;
  }

  /// Nombre legible del ambiente, para mostrarlo en pantalla y en los logs.
  static String get ambienteLabel {
    switch (ambiente) {
      case Ambiente.local:
        return 'LOCAL';
      case Ambiente.pruebas:
        return 'PRUEBAS';
      case Ambiente.produccion:
        return 'PRODUCCIÓN';
    }
  }

  /// true salvo en producción: sirve para pintar avisos que nunca deben
  /// aparecerle a un cajero en un build real.
  static bool get esAmbienteNoProductivo => ambiente != Ambiente.produccion;

  static String get baseUrl {
    if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
    switch (ambiente) {
      case Ambiente.local:
        return localUrl;
      case Ambiente.pruebas:
        if (pruebasUrl.isEmpty) {
          throw StateError(
            'ENV=pruebas no tiene URL fija: el ambiente de pruebas es un deploy '
            'preview de Vercel. Vuelve a compilar pasando la URL del preview '
            'actual, por ejemplo:\n'
            '  --dart-define=API_URL=https://<preview>.vercel.app/api/app',
          );
        }
        return pruebasUrl;
      case Ambiente.produccion:
        return produccionUrl;
    }
  }

  // Auth
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String cambiarTienda = '/auth/cambiar-tienda';

  // Productos: GET /productos/{tiendaId}
  static String productos(String tiendaId) => '/productos/$tiendaId';

  // Asociar código de barras a producto existente: POST /productos/agregar-codigo/{productoId}
  static String asociarCodigo(String productoId) =>
      '/productos/agregar-codigo/$productoId';

  // Período: GET/POST /periodo/{tiendaId}/actual|abrir
  static String periodoActual(String tiendaId) => '/periodo/$tiendaId/actual';
  static String periodoAbrir(String tiendaId) => '/periodo/$tiendaId/abrir';

  // Ventas: /venta/{tiendaId}/{periodoId}
  static String ventas(String tiendaId, String periodoId) =>
      '/venta/$tiendaId/$periodoId';
  static String ventaDetalle(String tiendaId, String periodoId, String ventaId) =>
      '/venta/$tiendaId/$periodoId/$ventaId';

  // Descuentos
  static const String descuentosPreview = '/descuentos/preview';

  // Transfer destinations: GET /transfer-destinations/{tiendaId}
  static String transferDestinations(String tiendaId) =>
      '/transfer-destinations/$tiendaId';

  // Resumen día (Punto de partida): GET /resumen-dia/{tiendaId}
  static String resumenDia(String tiendaId) => '/resumen-dia/$tiendaId';

  // Multimoneda: GET /monedas/{negocioId} · GET /tasas-cambio/{negocioId}
  static String monedas(String negocioId) => '/monedas/$negocioId';
  static String tasasCambio(String negocioId) => '/tasas-cambio/$negocioId';

  // Health/liveness: GET /health → { success, status, services: { database } }
  static const String health = '/health';

  // Timeouts
  // Reducidos de 30s: con red presente pero sin uplink real (portal cautivo),
  // una lectura API-first bloqueaba hasta 30s antes de caer a cache — justo
  // cuando el cajero necesita el POS instantáneo. 8s acota ese peor caso.
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 8);

  // Probe de alcanzabilidad: timeout corto para decidir rápido si el servidor
  // responde antes de intentar lecturas pesadas. Hace un GET a /health y exige
  // una respuesta sana (200 + success:true) para contar como alcanzable.
  static const Duration probeTimeout = Duration(seconds: 3);
}
