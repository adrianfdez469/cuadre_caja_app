import 'package:flutter/foundation.dart';
import '../core/utils/currency.dart';
import '../data/models/cart_model.dart';
import '../data/models/moneda_model.dart';
import '../services/sync_service.dart';

class MonedasProvider extends ChangeNotifier {
  final SyncService _syncService;

  MultimonedaConfig _config = MultimonedaConfig.empty;
  bool _isLoading = false;
  String? _error;

  MonedasProvider(this._syncService);

  MultimonedaConfig get config => _config;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get monedaBase => _config.monedaBase;
  Map<String, double> get tasasVigentes => _config.tasasVigentes;
  Map<String, double> get tasasConversion => _config.tasasConversion;
  List<NegocioMonedaModel> get monedasActivas => _config.monedasActivas;
  bool get hasMonedasAlternativas => _config.hasMonedasAlternativas;

  List<NegocioMonedaModel> get monedasAlternativas =>
      _config.monedasAlternativas();

  Map<String, List<double>> get denominacionesPorMoneda =>
      _config.denominacionesPorMoneda;

  /// Carga config multimoneda: cache local primero, luego red si hay conexión.
  Future<void> load(String negocioId, {String? fallbackMonedaBase}) async {
    if (negocioId.isEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _config = await _syncService.loadMultimonedaConfig(
        negocioId,
        fallbackMonedaBase: fallbackMonedaBase,
      );
    } catch (e) {
      _error = e.toString();
      print('⚠️ Error cargando multimoneda: $e');
      if (_config.negocioId.isEmpty && fallbackMonedaBase != null) {
        _config = MultimonedaConfig(
          negocioId: negocioId,
          monedaBase: fallbackMonedaBase,
        );
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Solo lectura desde disco (sin red).
  Future<void> loadFromCache(String negocioId, {String? fallbackMonedaBase}) async {
    if (negocioId.isEmpty) return;
    final cached = await _syncService.getMultimonedaConfigLocal(negocioId);
    if (cached != null) {
      _config = cached;
      notifyListeners();
    } else if (fallbackMonedaBase != null) {
      _config = MultimonedaConfig(
        negocioId: negocioId,
        monedaBase: fallbackMonedaBase,
      );
      notifyListeners();
    }
  }

  double convertToBase(double monto, String moneda) =>
      CurrencyUtils.convertToBase(
        monto,
        moneda,
        _config.tasasConversion,
        _config.monedaBase,
      );

  double convertFromBase(double montoBase, String moneda) =>
      CurrencyUtils.convertFromBase(
        montoBase,
        moneda,
        _config.tasasConversion,
        _config.monedaBase,
      );

  /// Precio de producto normalizado a moneda base del negocio.
  double precioEnBase(double precio, String? monedaPrecioCode) =>
      convertToBase(precio, monedaPrecioCode ?? monedaBase);

  /// Total del carrito en moneda base (convierte cada ítem según monedaPrecioCode).
  double cartTotal(List<CartItemModel> items) => items.fold<double>(
        0,
        (sum, item) =>
            sum +
            convertToBase(
              item.precio * item.cantidad,
              item.monedaPrecioCode ?? monedaBase,
            ),
      );

  String simboloFor(String monedaCode) {
    for (final m in monedasActivas) {
      if (m.monedaCode == monedaCode) return m.simbolo;
    }
    return monedaCode;
  }

  void clear() {
    _config = MultimonedaConfig.empty;
    _error = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetConfig(MultimonedaConfig config) {
    _config = config;
    notifyListeners();
  }
}
