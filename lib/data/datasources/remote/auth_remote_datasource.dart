import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/usuario_model.dart';

class AuthResult {
  final UsuarioModel user;
  final String token;

  AuthResult({required this.user, required this.token});
}

class AuthRemoteDataSource {
  final ApiClient apiClient;

  AuthRemoteDataSource(this.apiClient);

  Future<AuthResult> login(String usuario, String password) async {
    final response = await apiClient.dio.post(
      ApiConstants.login,
      data: {'usuario': usuario, 'password': password},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Error de autenticación');
    }

    return AuthResult(
      user: UsuarioModel.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<AuthResult> refreshToken() async {
    final response = await apiClient.dio.post(ApiConstants.refresh);

    final data = response.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Error refrescando token');
    }

    return AuthResult(
      user: UsuarioModel.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<AuthResult> cambiarTienda(String tiendaId) async {
    final response = await apiClient.dio.post(
      ApiConstants.cambiarTienda,
      data: {'tiendaId': tiendaId},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Error cambiando tienda');
    }

    return AuthResult(
      user: UsuarioModel.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }
}
