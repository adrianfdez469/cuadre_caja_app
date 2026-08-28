import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/storage_keys.dart';

/// Preferencia de modo oscuro/claro, persistida entre sesiones.
class ThemeModeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeModeProvider() {
    _load();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(StorageKeys.darkModeEnabled) ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.darkModeEnabled, enabled);
  }
}
