import '../../data/models/pago_multimoneda_model.dart';

/// Utilidades de conversión multimoneda (misma lógica que el POS web).
///
/// CUP es el ancla universal (tasa = 1). El resto de tasas significa:
/// 1 [monedaCode] = tasas[monedaCode] CUP.
/// La conversión a [monedaBase] usa el cociente de tasas CUP.
class CurrencyUtils {
  CurrencyUtils._();

  static double cupTasa(String code, Map<String, double> tasas) {
    if (code == 'CUP') return 1;
    return tasas[code] ?? 1;
  }

  /// Convierte [monto] en [moneda] → unidades de [monedaBase].
  static double convertToBase(
    double monto,
    String moneda,
    Map<String, double> tasas,
    String monedaBase,
  ) {
    return (monto * cupTasa(moneda, tasas)) / cupTasa(monedaBase, tasas);
  }

  /// Convierte [montoBase] en [monedaBase] → unidades de [moneda].
  static double convertFromBase(
    double montoBase,
    String moneda,
    Map<String, double> tasas,
    String monedaBase,
  ) {
    final tasa = cupTasa(moneda, tasas);
    if (tasa == 0) return 0;
    return (montoBase * cupTasa(monedaBase, tasas)) / tasa;
  }

  /// Distribución automática de vuelto (Fase 2 — desglose de cobro).
  static List<VueltoLinea> calcularVuelto({
    required double totalBase,
    required List<PagoLinea> pagos,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required Map<String, List<double>> denominaciones,
  }) {
    final totalPagadoBase = pagos.fold<double>(
      0,
      (sum, p) => sum + convertToBase(p.monto, p.moneda, tasas, monedaBase),
    );
    final vueltoTotalBase = totalPagadoBase - totalBase;
    if (vueltoTotalBase < 0.0001) return [];

    final result = <VueltoLinea>[];

    if (monedaCobro != monedaBase) {
      final vueltoEnMonedaCobroRaw = convertFromBase(
        vueltoTotalBase,
        monedaCobro,
        tasas,
        monedaBase,
      );
      final denomsOrdenadas = List<double>.from(
        denominaciones[monedaCobro] ?? [],
      )..sort((a, b) => b.compareTo(a));
      final denomMin = denomsOrdenadas.isEmpty ? 1.0 : denomsOrdenadas.last;
      final vueltoEnMonedaCobro =
          (vueltoEnMonedaCobroRaw / denomMin).round() * denomMin;

      if (vueltoEnMonedaCobro > 0) {
        result.add(VueltoLinea(moneda: monedaCobro, monto: vueltoEnMonedaCobro));
      }

      final restoBase = vueltoTotalBase -
          convertToBase(vueltoEnMonedaCobro, monedaCobro, tasas, monedaBase);

      if (restoBase > 0.0001) {
        final denomsBase = List<double>.from(
          denominaciones[monedaBase] ?? [],
        )..sort((a, b) => b.compareTo(a));
        final denomMinBase = denomsBase.isEmpty ? 1.0 : denomsBase.last;
        final vueltoEnBase =
            (restoBase / denomMinBase).ceil() * denomMinBase;
        result.add(VueltoLinea(moneda: monedaBase, monto: vueltoEnBase));
      }
    } else {
      final denomsBase = List<double>.from(
        denominaciones[monedaBase] ?? [],
      )..sort((a, b) => b.compareTo(a));
      final denomMinBase = denomsBase.isEmpty ? 1.0 : denomsBase.last;
      final vueltoEnBase =
          (vueltoTotalBase / denomMinBase).ceil() * denomMinBase;
      if (vueltoEnBase > 0) {
        result.add(VueltoLinea(moneda: monedaBase, monto: vueltoEnBase));
      }
    }

    return result;
  }

  /// Snapshot congelado para POST venta (sin monedaBase).
  static Map<String, double> buildTasaSnapshot(Map<String, double> vigentes) {
    return Map<String, double>.from(vigentes);
  }
}
