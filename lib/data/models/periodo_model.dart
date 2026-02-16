class PeriodoModel {
  final String id;
  final String tiendaId;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final bool estaAbierto;
  final double totalVentas;
  final double totalGanancia;
  final double totalInversion;
  final double totalTransferencia;

  PeriodoModel({
    required this.id,
    required this.tiendaId,
    required this.fechaInicio,
    this.fechaFin,
    required this.estaAbierto,
    this.totalVentas = 0,
    this.totalGanancia = 0,
    this.totalInversion = 0,
    this.totalTransferencia = 0,
  });

  factory PeriodoModel.fromJson(Map<String, dynamic> json, {bool? estaAbierto}) {
    final periodo = json['periodo'] as Map<String, dynamic>?;
    final data = periodo ?? json;

    return PeriodoModel(
      id: data['id'] as String? ?? '',
      tiendaId: data['tiendaId'] as String? ?? '',
      fechaInicio: DateTime.parse(data['fechaInicio'] as String),
      fechaFin: data['fechaFin'] != null
          ? DateTime.parse(data['fechaFin'] as String)
          : null,
      estaAbierto: estaAbierto ?? json['estaAbierto'] as bool? ?? data['fechaFin'] == null,
      totalVentas: (data['totalVentas'] as num?)?.toDouble() ?? 0,
      totalGanancia: (data['totalGanancia'] as num?)?.toDouble() ?? 0,
      totalInversion: (data['totalInversion'] as num?)?.toDouble() ?? 0,
      totalTransferencia: (data['totalTransferencia'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tiendaId': tiendaId,
    'fechaInicio': fechaInicio.toIso8601String(),
    'fechaFin': fechaFin?.toIso8601String(),
    'estaAbierto': estaAbierto,
    'totalVentas': totalVentas,
    'totalGanancia': totalGanancia,
    'totalInversion': totalInversion,
    'totalTransferencia': totalTransferencia,
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'tiendaId': tiendaId,
    'fechaInicio': fechaInicio.toIso8601String(),
    'fechaFin': fechaFin?.toIso8601String(),
    'estaAbierto': estaAbierto ? 1 : 0,
    'totalVentas': totalVentas,
    'totalGanancia': totalGanancia,
    'totalInversion': totalInversion,
    'totalTransferencia': totalTransferencia,
  };

  factory PeriodoModel.fromMap(Map<String, dynamic> map) => PeriodoModel(
    id: map['id'] as String,
    tiendaId: map['tiendaId'] as String,
    fechaInicio: DateTime.parse(map['fechaInicio'] as String),
    fechaFin: map['fechaFin'] != null
        ? DateTime.parse(map['fechaFin'] as String)
        : null,
    estaAbierto: (map['estaAbierto'] as int) == 1,
    totalVentas: (map['totalVentas'] as num?)?.toDouble() ?? 0,
    totalGanancia: (map['totalGanancia'] as num?)?.toDouble() ?? 0,
    totalInversion: (map['totalInversion'] as num?)?.toDouble() ?? 0,
    totalTransferencia: (map['totalTransferencia'] as num?)?.toDouble() ?? 0,
  );
}
