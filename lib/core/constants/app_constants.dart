class AppConstants {
  static const String appName = 'Cuadre de Caja';
  /// Versión mostrada en la app y usada en nombres de APK (ej. app-arm64-v8a-release_v0.0.3.apk).
  /// Mantener en sync con pubspec.yaml version (solo parte semver, ej. 0.0.3 o 1.0.0).
  static const String appVersion = '1.0.2';

  /// ID del archivo releases.json en la carpeta de Drive (compartido "cualquiera con el enlace").
  /// Obtener el ID desde la URL: https://drive.google.com/file/d/ESTE_ES_EL_ID/view
  static const String driveReleasesJsonFileId = '1ekvyYpK0K693H0fYskQO4qMlM1vgkmrv';
  /// Carpeta pública de Drive con los APK y roadmap.json
  static const String driveFolderUrl =
      'https://drive.google.com/drive/folders/16LfxLzdav-PUsn97EcSnTdcNZcZnYukd';

  /// ID del archivo roadmap.json en la misma carpeta (changelog por versión).
  /// Opcional: si está vacío, el changelog puede venir dentro de releases.json como "changelog".
  static const String driveRoadmapJsonFileId = '';

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

