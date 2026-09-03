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
    final tasaBase = cupTasa(monedaBase, tasas);
    // Snapshot de tasas corrupto (base = 0): evitar dividir por cero, que
    // propagaría Infinity a los totales de pago y al cálculo de vuelto.
    if (tasaBase == 0) return 0;
    return (monto * cupTasa(moneda, tasas)) / tasaBase;
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

  /// Denominación más pequeña de [moneda]; 1 si el servidor no las trae.
  static double denominacionMinima(
    String moneda,
    Map<String, List<double>> denominaciones,
  ) {
    final denoms = (denominaciones[moneda] ?? const <double>[])
        .where((d) => d > 0)
        .toList()
      ..sort();
    return denoms.isEmpty ? 1.0 : denoms.first;
  }

  /// Vuelto pendiente en moneda base: lo pagado menos lo debido. Cero si falta.
  static double _vueltoPendiente(
    double totalBase,
    List<PagoLinea> pagos,
    Map<String, double> tasas,
    String monedaBase,
  ) {
    final pagado = pagos.fold<double>(
      0,
      (sum, p) => sum + convertToBase(p.monto, p.moneda, tasas, monedaBase),
    );
    final vuelto = pagado - totalBase;
    return vuelto < 0.0001 ? 0 : vuelto;
  }

  /// Repartos posibles del vuelto, del que más entrega en [monedaCobro] al que
  /// menos.
  ///
  /// Para cada denominación de la moneda con la que pagó el cliente se entrega
  /// el mayor múltiplo que cabe en lo adeudado, y el resto en la moneda más
  /// fina. Con 8,52 USD a dar, denominaciones `[1,5,10,20,50,100]` y 1 USD =
  /// 675 CUP salen tres: `8 USD + 351 CUP`, `5 USD + 2376 CUP` y `5751 CUP`.
  ///
  /// La primera es el reparto por defecto — la que devuelve [calcularVuelto].
  ///
  /// Todo se trunca a la denominación mínima de cada moneda, así que ningún
  /// reparto lleva fracciones ni entrega más de lo debido; lo que quede por
  /// debajo de la denominación más fina no se entrega.
  static List<Map<String, double>> variantesDeVuelto({
    required double vueltoTotalBase,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required Map<String, List<double>> denominaciones,
    List<String>? monedasVuelto,
    int max = 4,
  }) {
    if (vueltoTotalBase < 0.0001) return const [];

    final elegibles = monedasVuelto == null || monedasVuelto.isEmpty
        ? <String>{monedaCobro, monedaBase}
        : monedasVuelto.toSet();

    final fina = monedaMasFina(
      monedas: elegibles,
      denominaciones: denominaciones,
      tasas: tasas,
      monedaBase: monedaBase,
    );

    /// Entrega en [moneda] el mayor múltiplo de [paso] que cabe en [restante],
    /// y devuelve lo que queda sin repartir.
    ///
    /// Se trunca contando céntimos enteros, no dividiendo dobles: `8.52 - 8`
    /// da `0.5199999...`, que a 675 CUP/USD son `350.99999...` y se truncaban a
    /// 350 en vez de a los 351 que tocan.
    (double monto, double restante) tomar(
      String moneda,
      double paso,
      double restante,
    ) {
      final centimos =
          (convertFromBase(restante, moneda, tasas, monedaBase) * 100).round();
      final pasoCentimos = (paso * 100).round();
      if (centimos <= 0 || pasoCentimos <= 0) return (0, restante);
      final monto = (centimos ~/ pasoCentimos) * pasoCentimos / 100;
      if (monto <= 0) return (0, restante);
      return (monto, restante - convertToBase(monto, moneda, tasas, monedaBase));
    }

    /// Cierra un reparto poniendo lo que quede en la moneda más fina.
    Map<String, double> completar(Map<String, double> parcial, double restante) {
      final (monto, _) = tomar(
        fina,
        denominacionMinima(fina, denominaciones),
        restante,
      );
      final reparto = Map<String, double>.from(parcial);
      if (monto > 0) reparto[fina] = (reparto[fina] ?? 0) + monto;
      return reparto;
    }

    // Pagar en la moneda más fina (o en una que la caja no maneja) no da
    // variantes: partirla por denominaciones son repartos distintos del mismo
    // total, que no le sirven de nada al cajero.
    if (monedaCobro == fina || !elegibles.contains(monedaCobro)) {
      final unica = completar({}, vueltoTotalBase);
      return unica.isEmpty ? const [] : [unica];
    }

    final pasos = (denominaciones[monedaCobro] ?? const <double>[])
        .where((d) => d > 0)
        .toSet()
        .toList()
      ..sort();
    if (pasos.isEmpty) pasos.add(1);

    final variantes = <Map<String, double>>[];
    for (final paso in pasos) {
      final (monto, restante) = tomar(monedaCobro, paso, vueltoTotalBase);
      final reparto = completar(
        monto > 0 ? {monedaCobro: monto} : {},
        restante,
      );
      if (reparto.isEmpty) continue;
      final yaEsta = variantes.any(
        (v) =>
            v.length == reparto.length &&
            v.entries.every((e) => (reparto[e.key] ?? -1) == e.value),
      );
      if (!yaEsta) variantes.add(reparto);
      if (variantes.length == max) break;
    }
    return variantes;
  }

  /// Reparto automático del vuelto: la primera de [variantesDeVuelto], que es
  /// la que más entrega en la moneda que el cliente tiene en la mano.
  static List<VueltoLinea> calcularVuelto({
    required double totalBase,
    required List<PagoLinea> pagos,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required Map<String, List<double>> denominaciones,
    List<String>? monedasVuelto,
  }) {
    final variantes = variantesDeVuelto(
      vueltoTotalBase: _vueltoPendiente(totalBase, pagos, tasas, monedaBase),
      monedaCobro: monedaCobro,
      monedaBase: monedaBase,
      tasas: tasas,
      denominaciones: denominaciones,
      monedasVuelto: monedasVuelto,
      max: 1,
    );
    if (variantes.isEmpty) return [];
    return [
      for (final e in variantes.first.entries)
        if (e.value > 0) VueltoLinea(moneda: e.key, monto: e.value),
    ];
  }

  /// Moneda con la que se afina más el vuelto: aquella cuya denominación mínima
  /// vale menos en moneda base.
  static String monedaMasFina({
    required Iterable<String> monedas,
    required Map<String, List<double>> denominaciones,
    required Map<String, double> tasas,
    required String monedaBase,
  }) {
    var elegida = monedaBase;
    var mejor = double.infinity;
    for (final m in monedas) {
      final valor = convertToBase(
        denominacionMinima(m, denominaciones),
        m,
        tasas,
        monedaBase,
      );
      // El `<` estricto hace que, a igualdad, gane la primera — y el orden
      // arranca por la de cobro, que es la preferida.
      if (valor > 0 && valor < mejor) {
        mejor = valor;
        elegida = m;
      }
    }
    return elegida;
  }

}
