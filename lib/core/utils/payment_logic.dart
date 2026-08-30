import '../../data/models/moneda_model.dart';
import '../../data/models/pago_multimoneda_model.dart';
import '../../data/models/transfer_destination_model.dart';
import '../constants/bill_denominations.dart';
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
  /// admiten decimales, así que cualquier monto
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
  ///
  /// [hasItems] es la guarda contra vender la nada: vaciar el carrito desde la
  /// pantalla de cobro dejaba el total en 0 y, como el pago sembrado seguía
  /// ahí, `total <= 0` habilitaba el botón y se registraba una venta de 0 sin
  /// productos.
  static bool canConfirm({
    required double total,
    required bool falta,
    required double totalPagadoBase,
    required List<PagoLinea> pagosLinea,
    required bool hasPagos,
    bool hasTransferDestinations = true,
    bool hasItems = true,
  }) {
    if (!hasItems) return false;
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

  /// Montos rápidos que se ofrecen junto a "Exacto": para cada denominación de
  /// la moneda, el siguiente importe redondo que cubre el total. Es lo que el
  /// cliente entregaría de verdad — un billete más sobre lo que ya lleva.
  ///
  /// Con [exacto] 822 y denominaciones `[1, 5, 10, 20, 50, 100]` devuelve
  /// `[825, 830, 840]`: 820+5, 820+10 y 820+20. La de 1 no aparece porque su
  /// múltiplo es el propio 822, que ya es el botón "Exacto".
  ///
  /// Las denominaciones se ordenan aquí de menor a mayor: `MonedaInfoModel`
  /// las ordena por el campo `orden` del servidor, no por valor.
  static List<double> montosRapidos({
    required double exacto,
    required List<double> denominaciones,
    int cantidad = 3,
  }) {
    if (exacto <= 0) return const [];
    final denoms = denominaciones.where((d) => d > 0).toSet().toList()..sort();
    final montos = <double>[];
    for (final d in denoms) {
      final v = (exacto / d).ceil() * d;
      if (v > exacto && !montos.contains(v)) montos.add(v);
      if (montos.length == cantidad) break;
    }
    return montos;
  }

  /// Destino de transferencia preseleccionado: el único que haya, el marcado
  /// por defecto, o el primero. Cadena vacía si la tienda no tiene ninguno.
  static String defaultDestId(List<TransferDestinationModel> destinos) {
    if (destinos.isEmpty) return '';
    if (destinos.length == 1) return destinos.first.id;
    for (final d in destinos) {
      if (d.isDefault) return d.id;
    }
    return destinos.first.id;
  }

  /// Denominaciones por moneda con el respaldo de CUP: si el servidor no las
  /// trae, el cálculo del vuelto se quedaría sin denominación mínima.
  static Map<String, List<double>> denominacionesConFallback(
    MultimonedaConfig config,
  ) {
    final map = Map<String, List<double>>.from(config.denominacionesPorMoneda);
    if (map['CUP'] == null || map['CUP']!.isEmpty) {
      map['CUP'] = List<double>.from(BillDenominations.cup);
    }
    return map;
  }

  static List<VueltoLinea> calcularVueltoAuto({
    required double totalBase,
    required List<PagoLinea> pagos,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required Map<String, List<double>> denominaciones,
    List<String>? monedasVuelto,
  }) {
    return CurrencyUtils.calcularVuelto(
      totalBase: totalBase,
      pagos: pagos,
      monedaCobro: monedaCobro,
      monedaBase: monedaBase,
      tasas: tasas,
      denominaciones: denominaciones,
      monedasVuelto: monedasVuelto,
    );
  }

  /// Repartos posibles del vuelto; ver [CurrencyUtils.variantesDeVuelto].
  static List<Map<String, double>> variantesDeVuelto({
    required double vueltoTotalBase,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required Map<String, List<double>> denominaciones,
    List<String>? monedasVuelto,
    int max = 4,
  }) {
    return CurrencyUtils.variantesDeVuelto(
      vueltoTotalBase: vueltoTotalBase,
      monedaCobro: monedaCobro,
      monedaBase: monedaBase,
      tasas: tasas,
      denominaciones: denominaciones,
      monedasVuelto: monedasVuelto,
      max: max,
    );
  }

  /// Desglosa [monto] en billetes, del mayor al menor. Devuelve `null` si no se
  /// puede representar exactamente —monto con fracción, o denominaciones que no
  /// lo cubren (7 con billetes de 5 y 10)—: en ese caso la vista deja el conteo
  /// vacío y manda el monto tecleado, para que mirar los billetes nunca cambie
  /// el importe.
  ///
  /// Se cuenta en céntimos enteros: con dobles, un desglose "exacto" puede
  /// dejar un resto fantasma de 1e-13.
  static Map<double, int>? desglosarEnBilletes(
    double monto,
    List<double> denominaciones,
  ) {
    if (monto <= 0) return {};
    var restante = (monto * 100).round();
    final denoms = denominaciones.where((d) => d > 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final conteo = <double, int>{};
    for (final d in denoms) {
      final centimos = (d * 100).round();
      if (centimos <= 0 || restante < centimos) continue;
      final n = restante ~/ centimos;
      conteo[d] = n;
      restante -= n * centimos;
    }
    return restante == 0 ? conteo : null;
  }
}
