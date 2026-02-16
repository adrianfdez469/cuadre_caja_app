import 'package:flutter/foundation.dart';
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
      print('❌ Error cargando período: $e');
    }

    _isLoading = false;
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
