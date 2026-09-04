/// Respuesta de GET /api/app/tasas-cambio/{negocioId}.
class TasasVigentesResponse {
  /// Tasas ancladas en CUP: 1 `{monedaCode}` = `tasas[monedaCode]` CUP.
  ///
  /// Incluye la moneda base del negocio cuando no es CUP — convertir a la base
  /// pasa por CUP y necesita la tasa CUP de la propia base — y nunca incluye
  /// CUP, cuya tasa es implícitamente 1.
  final Map<String, double> tasas;
  final String monedaBase;
  final DateTime? actualizadoEn;

  const TasasVigentesResponse({
    this.tasas = const {},
    this.monedaBase = 'CUP',
    this.actualizadoEn,
  });

  /// Une `vigentes` y `tasasCup` en un solo mapa para hablar con las dos
  /// versiones del backend:
  ///
  /// - contrato v2.0.1: llega solo `vigentes`, ya completo.
  /// - contrato anterior: llega `vigentes` **sin la moneda base** más un
  ///   `tasasCup` completo. La unión recupera la base; quedarse con uno solo de
  ///   los dos objetos perdía claves (sin la base, toda conversión a base se
  ///   resolvía a tasa 1).
  ///
  /// Se descartan CUP y las tasas no positivas, igual que hace el servidor.
  factory TasasVigentesResponse.fromJson(Map<String, dynamic> json) {
    final tasas = <String, double>{};
    for (final raw in [json['vigentes'], json['tasasCup']]) {
      if (raw is! Map) continue;
      raw.forEach((k, v) {
        if (k == 'CUP' || v is! num) return;
        final tasa = v.toDouble();
        if (tasa <= 0) return;
        tasas.putIfAbsent(k as String, () => tasa);
      });
    }

    DateTime? actualizado;
    final actualizadoRaw = json['actualizadoEn'] as String?;
    if (actualizadoRaw != null) {
      actualizado = DateTime.tryParse(actualizadoRaw);
    }

    return TasasVigentesResponse(
      tasas: tasas,
      monedaBase: json['monedaBase'] as String? ?? 'CUP',
      actualizadoEn: actualizado,
    );
  }

  Map<String, dynamic> toJson() => {
        'vigentes': tasas,
        'monedaBase': monedaBase,
        if (actualizadoEn != null)
          'actualizadoEn': actualizadoEn!.toIso8601String(),
      };

  static const empty = TasasVigentesResponse();
}
