import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import 'secure_storage_service.dart';

/// Resultado de una operación de autenticación (refresh / re-login).
///
/// Distingue un rechazo definitivo del servidor (`authRejected`, p. ej. 401/403:
/// la sesión ya no sirve) de un fallo de red (`networkError`: timeout, sin
/// uplink real). Permite una política de logout conservadora: solo expulsar al
/// usuario ante un rechazo real, nunca por una red inestable.
enum AuthResult { ok, authRejected, networkError }

class ApiClient {
  final Dio _dio;
  final SecureStorageService _storageService;
  bool _isRefreshing = false;

  ApiClient(this._storageService)
      : _dio = Dio(BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: ApiConstants.connectTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));
  }

  Dio get dio => _dio;

  /// Timeout para lectura del token: evita que FlutterSecureStorage bloquee
  /// indefinidamente en algunos dispositivos/ABIs (ej. arm64-v8a).
  static const Duration _tokenReadTimeout = Duration(seconds: 5);

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    String? token;
    try {
      token = await _storageService.getToken().timeout(
        _tokenReadTimeout,
        onTimeout: () {
          print('⚠️ Timeout leyendo token, continuando sin Authorization');
          return null;
        },
      );
    } catch (e) {
      print('⚠️ Error leyendo token: $e');
    }
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    print('🌐 REQUEST[${options.method}] => ${options.path}');
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    print('✅ RESPONSE[${response.statusCode}] => ${response.requestOptions.path}');
    handler.next(response);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    print('❌ ERROR[${err.response?.statusCode}] => ${err.requestOptions.path}');

    // Si es 401 y no estamos ya refrescando, intentar refresh
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshed = await _tryRefreshToken() == AuthResult.ok;
        _isRefreshing = false;

        if (refreshed) {
          // Reintentar la petición original con el nuevo token
          final token = await _storageService.getToken().timeout(
            _tokenReadTimeout,
            onTimeout: () => null,
          );
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $token';

          final response = await _dio.fetch(opts);
          return handler.resolve(response);
        }
      } catch (_) {
        _isRefreshing = false;
      }
    }

    handler.next(err);
  }

  /// Refresca/valida el token usando /auth/refresh.
  ///
  /// Público para usarlo como probe de validación de sesión (no existe /health):
  /// un `ok` confirma que el servidor sigue aceptando la sesión y persiste un
  /// token nuevo. Devuelve `authRejected` si el servidor rechaza el token
  /// (401/403) y `networkError` ante fallos de red.
  Future<AuthResult> refreshToken() => _tryRefreshToken();

  /// Intenta refrescar el token usando /auth/refresh
  Future<AuthResult> _tryRefreshToken() async {
    try {
      final currentToken = await _storageService.getToken().timeout(
        _tokenReadTimeout,
        onTimeout: () => null,
      );
      if (currentToken == null) return AuthResult.networkError;

      final response = await Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $currentToken',
        },
      )).post(ApiConstants.refresh);

      if (response.statusCode == 200 && response.data['success'] == true) {
        final newToken = response.data['token'] as String;
        await _storageService.saveToken(newToken);

        if (response.data['user'] != null) {
          await _storageService.saveUser(
            response.data['user'] as Map<String, dynamic>,
          );
        }

        print('🔄 Token refrescado exitosamente');
        return AuthResult.ok;
      }
      // Respuesta 2xx sin success: token no aceptado.
      return AuthResult.authRejected;
    } on DioException catch (e) {
      print('❌ Error refrescando token: ${e.message}');
      return _classifyDioError(e);
    } catch (e) {
      print('❌ Error refrescando token: $e');
      return AuthResult.networkError;
    }
  }

  /// Intenta re-login con credenciales guardadas. Devuelve bool por compatibilidad.
  Future<bool> tryReLogin() async => await reLogin() == AuthResult.ok;

  /// Re-login con credenciales guardadas, distinguiendo rechazo de fallo de red.
  Future<AuthResult> reLogin() async {
    try {
      final credentials = await _storageService.getCredentials().timeout(
        _tokenReadTimeout,
        onTimeout: () => null,
      );
      // Sin credenciales guardadas no hay forma de recuperar la sesión:
      // se trata como rechazo definitivo (requiere login manual).
      if (credentials == null) return AuthResult.authRejected;

      final response = await _dio.post(ApiConstants.login, data: credentials);
      if (response.statusCode == 200 && response.data['success'] == true) {
        await _storageService.saveToken(response.data['token'] as String);
        await _storageService.saveUser(
          response.data['user'] as Map<String, dynamic>,
        );
        print('🔄 Re-login exitoso');
        return AuthResult.ok;
      }
      return AuthResult.authRejected;
    } on DioException catch (e) {
      print('❌ Error en re-login: ${e.message}');
      return _classifyDioError(e);
    } catch (e) {
      print('❌ Error en re-login: $e');
      return AuthResult.networkError;
    }
  }

  /// Un 401/403 del servidor es un rechazo de credenciales/sesión; cualquier
  /// otro fallo (timeout, sin respuesta, 5xx) se trata como problema de red
  /// para no expulsar al usuario ante conectividad inestable.
  AuthResult _classifyDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) return AuthResult.authRejected;
    return AuthResult.networkError;
  }
}
