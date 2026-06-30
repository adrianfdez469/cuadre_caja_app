import 'package:flutter/foundation.dart';
import '../core/network/api_client.dart';
import '../core/network/secure_storage_service.dart';
import '../data/datasources/remote/auth_remote_datasource.dart';
import '../data/models/usuario_model.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthRemoteDataSource _authRemote;
  final SecureStorageService _storageService;
  final ApiClient _apiClient;

  AuthStatus _status = AuthStatus.initial;
  UsuarioModel? _usuario;
  String? _errorMessage;

  AuthProvider({
    required AuthRemoteDataSource authRemote,
    required SecureStorageService storageService,
    required ApiClient apiClient,
  })  : _authRemote = authRemote,
        _storageService = storageService,
        _apiClient = apiClient;

  AuthStatus get status => _status;
  UsuarioModel? get usuario => _usuario;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  String get tiendaId => _usuario?.localActual.id ?? '';
  String get tiendaNombre => _usuario?.localActual.nombre ?? '';
  String get negocioId => _usuario?.negocio.id ?? '';
  String get monedaBase => _usuario?.negocio.monedaBase ?? 'CUP';
  String get monedaFuerte => _usuario?.negocio.monedaFuerte ?? 'CUP';
  List<TiendaModel> get locales => _usuario?.locales ?? [];

  /// Intenta restaurar sesión con datos cacheados (token + usuario en cache).
  Future<bool> tryRestoreSession() async {
    try {
      final token = await _storageService.getToken();
      final userData = await _storageService.getUser();

      if (token != null && userData != null) {
        _usuario = UsuarioModel.fromJson(userData);
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }
    } catch (e) {
      print('⚠️ Error restaurando sesión: $e');
    }

    _status = AuthStatus.unauthenticated;
    notifyListeners();
    return false;
  }

  /// Recarga el usuario desde el storage (útil tras refresh de token en segundo plano).
  Future<void> reloadUserFromStorage() async {
    try {
      final userData = await _storageService.getUser();
      if (userData != null) {
        _usuario = UsuarioModel.fromJson(userData);
        notifyListeners();
      }
    } catch (e) {
      print('⚠️ Error recargando usuario: $e');
    }
  }

  /// Login con usuario y contraseña
  Future<bool> login(String usuario, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authRemote.login(usuario, password);

      await _storageService.saveToken(result.token);
      await _storageService.saveUser(result.user.toJson());
      await _storageService.saveCredentials(usuario, password);

      _usuario = result.user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = _parseError(e);
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Refresca token
  Future<bool> refreshToken() async {
    try {
      final result = await _authRemote.refreshToken();
      await _storageService.saveToken(result.token);
      await _storageService.saveUser(result.user.toJson());
      _usuario = result.user;
      notifyListeners();
      return true;
    } catch (_) {
      // Intentar re-login automático
      return await _apiClient.tryReLogin();
    }
  }

  /// Cambia la tienda activa
  Future<bool> cambiarTienda(String tiendaId) async {
    try {
      final result = await _authRemote.cambiarTienda(tiendaId);
      await _storageService.saveToken(result.token);
      await _storageService.saveUser(result.user.toJson());
      _usuario = result.user;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = _parseError(e);
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    await _storageService.clearAll();
    _usuario = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  String _parseError(dynamic e) {
    if (e.toString().contains('401')) return 'Usuario o contraseña incorrectos';
    if (e.toString().contains('403')) return 'No tienes acceso. Contacta al administrador.';
    // Errores de red (SocketException, timeout, conexión rechazada, etc.)
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('connection') ||
        msg.contains('connectionrefused') ||
        msg.contains('connection timed out') ||
        msg.contains('handshake') ||
        msg.contains('failed host lookup')) {
      return 'Sin conexión a internet. Revisa WiFi/datos.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  @visibleForTesting
  void debugSetUsuario(UsuarioModel usuario) {
    _usuario = usuario;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }
}
