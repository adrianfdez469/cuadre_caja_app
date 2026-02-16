class AppConstants {
  static const String appName = 'Cuadre de Caja';
  static const String appVersion = '1.0.0';
  
  // Sincronización
  static const Duration syncInterval = Duration(seconds: 30);
  static const Duration productSyncInterval = Duration(minutes: 5);
  static const int maxSyncAttempts = 5;
  
  // Carrito
  static const String defaultCartName = 'Cuenta #1';
  
  // Database
  static const String databaseName = 'cuadre_caja.db';
  static const int databaseVersion = 1;
}

