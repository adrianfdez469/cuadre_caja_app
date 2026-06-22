import 'dart:convert';

/// Denominación de billete/moneda para desglose en cobro.
class DenominacionBilleteModel {
  final String id;
  final String monedaCode;
  final double valor;
  final bool activo;
  final int orden;

  const DenominacionBilleteModel({
    required this.id,
    required this.monedaCode,
    required this.valor,
    this.activo = true,
    this.orden = 0,
  });

  factory DenominacionBilleteModel.fromJson(Map<String, dynamic> json) =>
      DenominacionBilleteModel(
        id: json['id'] as String? ?? '',
        monedaCode: json['monedaCode'] as String? ?? '',
        valor: (json['valor'] as num?)?.toDouble() ?? 0,
        activo: json['activo'] as bool? ?? true,
        orden: (json['orden'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'monedaCode': monedaCode,
        'valor': valor,
        'activo': activo,
        'orden': orden,
      };
}

/// Metadatos globales de una moneda (nombre, símbolo, denominaciones).
class MonedaInfoModel {
  final String code;
  final String nombre;
  final String simbolo;
  final bool activo;
  final List<DenominacionBilleteModel> denominaciones;

  const MonedaInfoModel({
    required this.code,
    required this.nombre,
    required this.simbolo,
    this.activo = true,
    this.denominaciones = const [],
  });

  factory MonedaInfoModel.fromJson(Map<String, dynamic> json) {
    final denomsRaw = json['denominaciones'] as List<dynamic>? ?? [];
    return MonedaInfoModel(
      code: json['code'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      simbolo: json['simbolo'] as String? ?? '',
      activo: json['activo'] as bool? ?? true,
      denominaciones: denomsRaw
          .map((d) =>
              DenominacionBilleteModel.fromJson(d as Map<String, dynamic>))
          .where((d) => d.activo)
          .toList()
        ..sort((a, b) => b.orden.compareTo(a.orden)),
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'nombre': nombre,
        'simbolo': simbolo,
        'activo': activo,
        'denominaciones': denominaciones.map((d) => d.toJson()).toList(),
      };

  /// Valores de billetes activos, mayor a menor.
  List<double> get valoresDenominaciones =>
      denominaciones.map((d) => d.valor).toList();
}

/// Moneda habilitada para un negocio (GET /api/app/monedas/{negocioId}).
class NegocioMonedaModel {
  final String id;
  final String negocioId;
  final String monedaCode;
  final bool admiteEfectivo;
  final bool admiteTransferencia;
  final bool activo;
  final MonedaInfoModel? moneda;

  const NegocioMonedaModel({
    required this.id,
    required this.negocioId,
    required this.monedaCode,
    this.admiteEfectivo = true,
    this.admiteTransferencia = false,
    this.activo = true,
    this.moneda,
  });

  factory NegocioMonedaModel.fromJson(Map<String, dynamic> json) =>
      NegocioMonedaModel(
        id: json['id'] as String? ?? '',
        negocioId: json['negocioId'] as String? ?? '',
        monedaCode: json['monedaCode'] as String? ?? '',
        admiteEfectivo: json['admiteEfectivo'] as bool? ?? true,
        admiteTransferencia: json['admiteTransferencia'] as bool? ?? false,
        activo: json['activo'] as bool? ?? true,
        moneda: json['moneda'] != null
            ? MonedaInfoModel.fromJson(json['moneda'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'negocioId': negocioId,
        'monedaCode': monedaCode,
        'admiteEfectivo': admiteEfectivo,
        'admiteTransferencia': admiteTransferencia,
        'activo': activo,
        if (moneda != null) 'moneda': moneda!.toJson(),
      };

  String get simbolo => moneda?.simbolo ?? monedaCode;
}

class MonedasNegocioResponse {
  final List<NegocioMonedaModel> monedas;

  const MonedasNegocioResponse({required this.monedas});

  factory MonedasNegocioResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['monedas'] as List<dynamic>? ?? [];
    return MonedasNegocioResponse(
      monedas: raw
          .map((m) => NegocioMonedaModel.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'monedas': monedas.map((m) => m.toJson()).toList(),
      };
}

/// Configuración multimoneda cacheada (monedas + tasas) para offline.
class MultimonedaConfig {
  final String negocioId;
  final String monedaBase;
  /// Snapshot para POST venta (sin moneda base).
  final Map<String, double> tasasVigentes;
  /// Tasas ancladas en CUP para conversiones en UI y cobro.
  final Map<String, double> tasasConversion;
  final List<NegocioMonedaModel> monedas;
  final DateTime? tasasActualizadoEn;

  const MultimonedaConfig({
    required this.negocioId,
    required this.monedaBase,
    this.tasasVigentes = const {},
    this.tasasConversion = const {},
    this.monedas = const [],
    this.tasasActualizadoEn,
  });

  static const empty = MultimonedaConfig(negocioId: '', monedaBase: 'CUP');

  List<NegocioMonedaModel> get monedasActivas =>
      monedas.where((m) => m.activo).toList();

  bool _tieneTasaVigente(String monedaCode) {
    if (monedaCode == 'CUP') return true;
    final t = tasasConversion[monedaCode];
    return t != null && t > 0;
  }

  /// Monedas alternativas activas con tasa vigente (CUP siempre convertible).
  List<NegocioMonedaModel> monedasAlternativas() {
    return monedasActivas.where((m) {
      if (m.monedaCode == monedaBase) return false;
      return _tieneTasaVigente(m.monedaCode);
    }).toList();
  }

  bool get hasMonedasAlternativas => monedasAlternativas().isNotEmpty;

  /// Mapa monedaCode → valores de billetes (para desglose, Fase 2).
  Map<String, List<double>> get denominacionesPorMoneda {
    final map = <String, List<double>>{};
    for (final nm in monedasActivas) {
      final vals = nm.moneda?.valoresDenominaciones ?? [];
      if (vals.isNotEmpty) map[nm.monedaCode] = vals;
    }
    return map;
  }

  Map<String, dynamic> toCacheJson() => {
        'negocioId': negocioId,
        'monedaBase': monedaBase,
        'tasasVigentes': tasasVigentes,
        'tasasConversion': tasasConversion,
        'monedas': monedas.map((m) => m.toJson()).toList(),
        if (tasasActualizadoEn != null)
          'tasasActualizadoEn': tasasActualizadoEn!.toIso8601String(),
      };

  factory MultimonedaConfig.fromCacheJson(Map<String, dynamic> json) {
    final tasasRaw = json['tasasVigentes'] as Map<String, dynamic>? ?? {};
    final conversionRaw =
        json['tasasConversion'] as Map<String, dynamic>? ?? {};
    final monedasRaw = json['monedas'] as List<dynamic>? ?? [];
    DateTime? actualizado;
    final actualizadoRaw = json['tasasActualizadoEn'] as String?;
    if (actualizadoRaw != null) {
      actualizado = DateTime.tryParse(actualizadoRaw);
    }
    final vigentes = tasasRaw.map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    final conversion = conversionRaw.isNotEmpty
        ? conversionRaw.map((k, v) => MapEntry(k, (v as num).toDouble()))
        : vigentes;
    return MultimonedaConfig(
      negocioId: json['negocioId'] as String? ?? '',
      monedaBase: json['monedaBase'] as String? ?? 'CUP',
      tasasVigentes: vigentes,
      tasasConversion: conversion,
      monedas: monedasRaw
          .map((m) => NegocioMonedaModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      tasasActualizadoEn: actualizado,
    );
  }

  static MultimonedaConfig? fromCacheString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return MultimonedaConfig.fromCacheJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  String toCacheString() => jsonEncode(toCacheJson());
}
