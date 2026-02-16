import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import 'secure_storage_service.dart';

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

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storageService.getToken();
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
        final refreshed = await _tryRefreshToken();
        _isRefreshing = false;

        if (refreshed) {
          // Reintentar la petición original con el nuevo token
          final token = await _storageService.getToken();
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

  /// Refresca el token usando /auth/refresh (público para uso al iniciar o al reconectar).
  Future<bool> tryRefreshToken() async {
    return _tryRefreshToken();
  }

  /// Intenta refrescar el token usando /auth/refresh
  Future<bool> _tryRefreshToken() async {
    try {
      final currentToken = await _storageService.getToken();
      if (currentToken == null) return false;

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
        return true;
      }
    } catch (e) {
      print('❌ Error refrescando token: $e');
    }
    return false;
  }

  /// Intenta re-login con credenciales guardadas
  Future<bool> tryReLogin() async {
    try {
      final credentials = await _storageService.getCredentials();
      if (credentials == null) return false;

      final response = await _dio.post(ApiConstants.login, data: credentials);
      if (response.statusCode == 200 && response.data['success'] == true) {
        await _storageService.saveToken(response.data['token'] as String);
        await _storageService.saveUser(
          response.data['user'] as Map<String, dynamic>,
        );
        print('🔄 Re-login exitoso');
        return true;
      }
    } catch (e) {
      print('❌ Error en re-login: $e');
    }
    return false;
  }
}
