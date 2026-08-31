import 'package:flutter/foundation.dart';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import '../data/models/periodo_model.dart';
import '../services/sync_service.dart';

class PeriodoProvider extends ChangeNotifier {
  final SyncService _syncService;

  PeriodoModel? _periodo;
  bool _isLoading = false;
  String? _error;

  PeriodoProvider(this._syncService);

  PeriodoModel? get periodo => _periodo;
  bool get isLoading => _isLoading;
  bool get hasActivePeriodo => _periodo?.estaAbierto ?? false;
  String? get periodoId => _periodo?.id;
  String? get error => _error;

  /// Carga período actual (network-first)
  Future<void> loadPeriodo(String tiendaId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _periodo = await _syncService.loadPeriodoActual(tiendaId);
    } catch (e) {
      _error = e.toString();
      logDebug('❌ Error cargando período: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Solo lectura desde disco (sin red). El cache es espejo del servidor: si no
  /// hay fila, es que no hay período abierto.
  ///
  /// No toca `_isLoading` a propósito: esto corre tras cada sincronización, y
  /// hacerlo dejaría el botón "Abrir Período" parpadeando deshabilitado.
  Future<void> loadFromCache(String tiendaId) async {
    _periodo = await _syncService.getPeriodoLocal(tiendaId);
    notifyListeners();
  }

  /// Abre un nuevo período
  Future<bool> abrirPeriodo(String tiendaId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _periodo = await _syncService.abrirPeriodo(tiendaId);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
