import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/storage_keys.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;
  late final SharedPreferences _prefs;
  bool _useSecureStorage = true;

  SecureStorageService(this._storage);

  /// Llamar una vez al inicio para detectar si secure storage funciona
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    try {
      await _storage.write(key: '__test__', value: 'test');
      final result = await _storage.read(key: '__test__');
      await _storage.delete(key: '__test__');

      if (result == 'test') {
        _useSecureStorage = true;
        print('✅ Usando FlutterSecureStorage');
      } else {
        _useSecureStorage = false;
        print('⚠️ FlutterSecureStorage no confiable, usando SharedPreferences');
      }
    } catch (e) {
      _useSecureStorage = false;
      print('⚠️ FlutterSecureStorage no disponible: $e');
    }
  }

  Future<void> _write(String key, String value) async {
    if (_useSecureStorage) {
      await _storage.write(key: key, value: value);
    } else {
      await _prefs.setString(key, value);
    }
  }

  Future<String?> _read(String key) async {
    if (_useSecureStorage) {
      return await _storage.read(key: key);
    } else {
      return _prefs.getString(key);
    }
  }

  Future<void> _delete(String key) async {
    if (_useSecureStorage) {
      await _storage.delete(key: key);
    } else {
      await _prefs.remove(key);
    }
  }

  Future<void> _deleteAll() async {
    if (_useSecureStorage) {
      await _storage.deleteAll();
    } else {
      await _prefs.clear();
    }
  }

  // --- Token ---

  Future<void> saveToken(String token) async =>
      await _write(StorageKeys.authToken, token);

  Future<String?> getToken() async =>
      await _read(StorageKeys.authToken);

  Future<void> deleteToken() async =>
      await _delete(StorageKeys.authToken);

  // --- User data ---

  Future<void> saveUser(Map<String, dynamic> userData) async =>
      await _write(StorageKeys.userData, jsonEncode(userData));

  Future<Map<String, dynamic>?> getUser() async {
    final data = await _read(StorageKeys.userData);
    if (data != null) return jsonDecode(data) as Map<String, dynamic>;
    return null;
  }

  Future<void> deleteUser() async =>
      await _delete(StorageKeys.userData);

  // --- Credentials (para re-login automático) ---

  Future<void> saveCredentials(String usuario, String password) async =>
      await _write(
        StorageKeys.credentials,
        jsonEncode({'usuario': usuario, 'password': password}),
      );

  Future<Map<String, dynamic>?> getCredentials() async {
    final data = await _read(StorageKeys.credentials);
    if (data != null) return jsonDecode(data) as Map<String, dynamic>;
    return null;
  }

  // --- Clear ---

  Future<void> clearAll() async => await _deleteAll();
}
