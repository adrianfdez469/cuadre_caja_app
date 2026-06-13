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

  // Tasas de cambio (fuera de /api/app): GET /api/negocio/{negocioId}/tasas-cambio
  static String get negocioApiBaseUrl =>
      baseUrl.replaceAll('/api/app', '/api/negocio');

  static String tasasCambioUrl(String negocioId) =>
      '$negocioApiBaseUrl/$negocioId/tasas-cambio';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
