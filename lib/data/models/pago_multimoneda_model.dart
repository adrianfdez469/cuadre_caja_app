/// Línea de pago multimoneda (POST venta).
class PagoLinea {
  final String tipo; // cash | transfer
  final String moneda;
  final double monto;
  final double equivalenteBase;
  final String? transferDestinationId;

  const PagoLinea({
    required this.tipo,
    required this.moneda,
    required this.monto,
    required this.equivalenteBase,
    this.transferDestinationId,
  });

  factory PagoLinea.fromJson(Map<String, dynamic> json) => PagoLinea(
        tipo: json['tipo'] as String? ?? 'cash',
        moneda: json['moneda'] as String? ?? 'CUP',
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
        equivalenteBase: (json['equivalenteBase'] as num?)?.toDouble() ?? 0,
        transferDestinationId: json['transferDestinationId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'moneda': moneda,
        'monto': monto,
        'equivalenteBase': equivalenteBase,
        if (transferDestinationId != null)
          'transferDestinationId': transferDestinationId,
      };
}

/// Línea de vuelto multimoneda (POST venta).
class VueltoLinea {
  final String moneda;
  final double monto;

  const VueltoLinea({required this.moneda, required this.monto});

  factory VueltoLinea.fromJson(Map<String, dynamic> json) => VueltoLinea(
        moneda: json['moneda'] as String? ?? 'CUP',
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'moneda': moneda,
        'monto': monto,
      };
}
