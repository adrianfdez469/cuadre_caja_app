/// Respuesta de GET /api/app/tasas-cambio/{negocioId}.
class TasasVigentesResponse {
  /// Snapshot para ventas (sin moneda base ni CUP).
  final Map<String, double> vigentes;
  /// Tasas ancladas en CUP para conversiones (incluye moneda base).
  final Map<String, double> tasasCup;
  final String monedaBase;
  final DateTime? actualizadoEn;

  const TasasVigentesResponse({
    required this.vigentes,
    this.tasasCup = const {},
    this.monedaBase = 'CUP',
    this.actualizadoEn,
  });

  factory TasasVigentesResponse.fromJson(Map<String, dynamic> json) {
    final vigentesRaw = json['vigentes'] as Map<String, dynamic>? ?? {};
    final tasasCupRaw = json['tasasCup'] as Map<String, dynamic>? ?? {};
    DateTime? actualizado;
    final actualizadoRaw = json['actualizadoEn'] as String?;
    if (actualizadoRaw != null) {
      actualizado = DateTime.tryParse(actualizadoRaw);
    }
    final vigentes = vigentesRaw.map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    final tasasCup = tasasCupRaw.map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    return TasasVigentesResponse(
      vigentes: vigentes,
      tasasCup: tasasCup.isNotEmpty ? tasasCup : vigentes,
      monedaBase: json['monedaBase'] as String? ?? 'CUP',
      actualizadoEn: actualizado,
    );
  }

  Map<String, dynamic> toJson() => {
        'vigentes': vigentes,
        'tasasCup': tasasCup,
        'monedaBase': monedaBase,
        if (actualizadoEn != null)
          'actualizadoEn': actualizadoEn!.toIso8601String(),
      };

  /// Objeto a enviar como `tasaSnapshot` en ventas (sin monedaBase).
  Map<String, double> get snapshot => Map<String, double>.from(vigentes);

  static const empty = TasasVigentesResponse(vigentes: {});
}
