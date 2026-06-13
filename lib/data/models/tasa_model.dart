/// Respuesta de GET /api/negocio/{negocioId}/tasas-cambio.
class TasasVigentesResponse {
  final Map<String, double> vigentes;
  final String monedaBase;

  const TasasVigentesResponse({
    required this.vigentes,
    this.monedaBase = 'CUP',
  });

  factory TasasVigentesResponse.fromJson(Map<String, dynamic> json) {
    final vigentesRaw = json['vigentes'] as Map<String, dynamic>? ?? {};
    return TasasVigentesResponse(
      vigentes: vigentesRaw.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      monedaBase: json['monedaBase'] as String? ?? 'CUP',
    );
  }

  Map<String, dynamic> toJson() => {
        'vigentes': vigentes,
        'monedaBase': monedaBase,
      };

  /// Objeto a enviar como `tasaSnapshot` en ventas.
  Map<String, double> get snapshot => Map<String, double>.from(vigentes);

  static const empty = TasasVigentesResponse(vigentes: {});
}
