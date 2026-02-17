class ServerException implements Exception {
  final String message;
  
  ServerException(this.message);
  
  @override
  String toString() => 'ServerException: $message';
}

class CacheException implements Exception {
  final String message;
  
  CacheException(this.message);
  
  @override
  String toString() => 'CacheException: $message';
}

class NetworkException implements Exception {
  final String message;
  
  NetworkException(this.message);
  
  @override
  String toString() => 'NetworkException: $message';
}

class AuthException implements Exception {
  final String message;
  
  AuthException(this.message);
  
  @override
  String toString() => 'AuthException: $message';
}

/// Excepción cuando el servidor rechaza la creación/sincronización de una venta.
/// El [message] es el texto devuelto por el API en el campo "error".
class SyncVentaException implements Exception {
  final String message;

  SyncVentaException(this.message);

  @override
  String toString() => message;
}

