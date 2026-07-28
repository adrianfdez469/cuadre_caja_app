import '../../data/models/pago_multimoneda_model.dart';
import 'currency.dart';

/// Estado de pago por moneda (efectivo + transferencia en modo mixto).
class PagoMonedaState {
  final double cash;
  final double transfer;
  final String transferDestId;

  const PagoMonedaState({
    this.cash = 0,
    this.transfer = 0,
    this.transferDestId = '',
  });

  PagoMonedaState copyWith({
    double? cash,
    double? transfer,
    String? transferDestId,
  }) {
    return PagoMonedaState(
      cash: cash ?? this.cash,
      transfer: transfer ?? this.transfer,
      transferDestId: transferDestId ?? this.transferDestId,
    );
  }

  double get total => cash + transfer;
}

/// Lógica pura de cobro multimoneda (sin dependencias de UI).
class PaymentLogic {
  PaymentLogic._();

  static List<PagoLinea> buildPagosLinea(
    Map<String, PagoMonedaState> pagos,
    String monedaBase,
    Map<String, double> tasas,
  ) {
    final lines = <PagoLinea>[];
    for (final entry in pagos.entries) {
      final moneda = entry.key;
      final pago = entry.value;
      if (pago.cash > 0) {
        lines.add(PagoLinea(
          tipo: 'cash',
          moneda: moneda,
          monto: pago.cash,
          equivalenteBase: CurrencyUtils.convertToBase(
            pago.cash,
            moneda,
            tasas,
            monedaBase,
          ),
        ));
      }
      if (pago.transfer > 0) {
        lines.add(PagoLinea(
          tipo: 'transfer',
          moneda: moneda,
          monto: pago.transfer,
          equivalenteBase: CurrencyUtils.convertToBase(
            pago.transfer,
            moneda,
            tasas,
            monedaBase,
          ),
          transferDestinationId:
              pago.transferDestId.isNotEmpty ? pago.transferDestId : null,
        ));
      }
    }
    return lines;
  }

  static double totalPagadoBase(
    Map<String, PagoMonedaState> pagos,
    String monedaBase,
    Map<String, double> tasas,
  ) {
    return buildPagosLinea(pagos, monedaBase, tasas)
        .fold<double>(0, (sum, p) => sum + p.equivalenteBase);
  }

  static bool falta(double total, double totalPagadoBase) =>
      (totalPagadoBase * 100).round() < (total * 100).round();

  /// Redondea un monto de efectivo al entero superior. Los campos de efectivo no
  /// admiten decimales (ver [CashAmountInputFormatter]), así que cualquier monto
  /// predefinido o sugerido debe cubrir el total redondeando hacia arriba: si se
  /// usara el total crudo (p. ej. 3.25) el campo mostraría "3" (truncado) mientras
  /// internamente se cobraba 3.25, dejando la pantalla inconsistente
  /// ("Efectivo 3 / Total 3.25 / Cambio 0"). Se redondea a céntimos primero para
  /// que un 3.00 con ruido de coma flotante no suba a 4.
  static double ceilCash(double amount) {
    if (amount <= 0) return 0;
    final cents = (amount * 100).round();
    return (cents / 100).ceilToDouble();
  }

  static double vueltoTotalBase({
    required double total,
    required double totalPagadoBase,
    required bool falta,
  }) {
    if (falta) return 0;
    return (totalPagadoBase - total).clamp(0, double.infinity);
  }

  static double suggestCash({
    required double total,
    required Map<String, PagoMonedaState> pagos,
    required String moneda,
    required String monedaBase,
    required Map<String, double> tasas,
    String? excludeMoneda,
  }) {
    final otherPaid = pagos.entries
        .where((e) => e.key != excludeMoneda)
        .fold<double>(
          0,
          (s, e) => s +
              CurrencyUtils.convertToBase(
                e.value.total,
                e.key,
                tasas,
                monedaBase,
              ),
        );
    final rem = (total - otherPaid).clamp(0, double.infinity).toDouble();
    if (rem <= 0) return 0;
    final converted =
        CurrencyUtils.convertFromBase(rem, moneda, tasas, monedaBase);
    if (converted <= 0) return 0;
    return ceilCash(converted);
  }

  /// Al editar transferencia: resta del efectivo (efectivo + transferencia se mantiene).
  static ({double cash, double transfer}) applyMixedTransferEdit({
    required double currentCash,
    required double currentTransfer,
    required double newTransfer,
  }) {
    final newCash = (currentCash + currentTransfer - newTransfer)
        .clamp(0, double.infinity);
    return (
      cash: newCash.floorToDouble(),
      transfer: newTransfer,
    );
  }

  /// Al quitar transferencia: devuelve el monto al efectivo.
  static ({double cash, double transfer}) collapseTransferToCash({
    required double cash,
    required double transfer,
  }) {
    if (transfer <= 0) {
      return (cash: cash, transfer: 0);
    }
    return (
      cash: (cash + transfer).floorToDouble(),
      transfer: 0,
    );
  }

  /// [hasTransferDestinations] indica si la tienda tiene destinos configurados.
  /// Solo entonces se exige elegir uno: si la tienda no tiene ninguno (o el
  /// cache local está vacío), exigirlo dejaba el botón deshabilitado sin que la
  /// UI ofreciera forma de seleccionarlo — un callejón sin salida. La venta se
  /// permite con `transferDestinationId` nulo, que el backend acepta.
  static bool canConfirm({
    required double total,
    required bool falta,
    required double totalPagadoBase,
    required List<PagoLinea> pagosLinea,
    required bool hasPagos,
    bool hasTransferDestinations = true,
  }) {
    if (total <= 0) return hasPagos;
    if (falta || totalPagadoBase <= 0) return false;
    if (!hasTransferDestinations) return true;
    for (final p in pagosLinea) {
      if (p.tipo == 'transfer' &&
          p.monto > 0 &&
          (p.transferDestinationId == null ||
              p.transferDestinationId!.isEmpty)) {
        return false;
      }
    }
    return true;
  }

  static List<VueltoLinea> calcularVueltoAuto({
    required double totalBase,
    required List<PagoLinea> pagos,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required Map<String, List<double>> denominaciones,
  }) {
    return CurrencyUtils.calcularVuelto(
      totalBase: totalBase,
      pagos: pagos,
      monedaCobro: monedaCobro,
      monedaBase: monedaBase,
      tasas: tasas,
      denominaciones: denominaciones,
    );
  }
}
