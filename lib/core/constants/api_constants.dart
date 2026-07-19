class ApiConstants {
  // Base URL - Cambiar por tu URL de producción
  // Para desarrollo local (macOS): usa localhost
  // Para dispositivos físicos: cambia a la IP de tu máquina
  // static const String baseUrl = 'http://localhost:3000/api/app';
  static const String baseUrl = 'https://cuadrecaja.ventario.cloud/api/app';
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

  // Timeouts
  // Reducidos de 30s: con red presente pero sin uplink real (portal cautivo),
  // una lectura API-first bloqueaba hasta 30s antes de caer a cache — justo
  // cuando el cajero necesita el POS instantáneo. 8s acota ese peor caso.
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 8);

  // Probe de alcanzabilidad: timeout corto para decidir rápido si el servidor
  // responde antes de intentar lecturas pesadas. No existe /health, así que se
  // hace un GET a la base y cualquier respuesta HTTP cuenta como alcanzable.
  static const Duration probeTimeout = Duration(seconds: 3);
}
