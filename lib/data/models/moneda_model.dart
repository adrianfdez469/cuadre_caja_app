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
  /// Tasas ancladas en CUP: 1 `{monedaCode}` = `tasas[monedaCode]` CUP.
  ///
  /// Un unico mapa para todo — precios del carrito, `equivalenteBase` de cada
  /// pago y el `tasaSnapshot` que se persiste con la venta. Incluye la moneda
  /// base del negocio cuando no es CUP: sin ella toda conversion a base se
  /// resuelve a tasa 1. Dos mapas separados es justo como se colaron snapshots
  /// sin la base, asi que a proposito hay uno solo.
  final Map<String, double> tasas;
  final List<NegocioMonedaModel> monedas;
  final DateTime? tasasActualizadoEn;

  const MultimonedaConfig({
    required this.negocioId,
    required this.monedaBase,
    this.tasas = const {},
    this.monedas = const [],
    this.tasasActualizadoEn,
  });

  static const empty = MultimonedaConfig(negocioId: '', monedaBase: 'CUP');

  List<NegocioMonedaModel> get monedasActivas =>
      monedas.where((m) => m.activo).toList();

  bool _tieneTasaVigente(String monedaCode) {
    if (monedaCode == 'CUP') return true;
    final t = tasas[monedaCode];
    return t != null && t > 0;
  }

  /// Si se puede convertir a la moneda base del negocio.
  ///
  /// Las tasas están ancladas en CUP, así que convertir a la base pasa por CUP
  /// y necesita la tasa CUP de la propia base. Sin ella `cupTasa(monedaBase)`
  /// cae a 1 y toda conversión queda inflada por el factor de la base — y el
  /// backend rechaza la venta con `MISSING_EXCHANGE_RATE`. Cobrar íntegramente
  /// en la base sí funciona: ahí la tasa se cancela.
  bool get puedeConvertirABase => _tieneTasaVigente(monedaBase);

  /// Monedas alternativas activas con tasa vigente (CUP siempre convertible).
  ///
  /// Vacía si no hay tasa de la propia base: cobrar en otra moneda registraría
  /// un monto equivocado, así que es mejor no ofrecerlo.
  List<NegocioMonedaModel> monedasAlternativas() {
    if (!puedeConvertirABase) return const [];
    return monedasActivas.where((m) {
      if (m.monedaCode == monedaBase) return false;
      return _tieneTasaVigente(m.monedaCode);
    }).toList();
  }

  bool get hasMonedasAlternativas => monedasAlternativas().isNotEmpty;

  /// Monedas en las que se puede cobrar: la base —siempre, no necesita
  /// conversión— más las alternativas convertibles.
  List<String> monedasCobrables() => [
        monedaBase,
        for (final m in monedasAlternativas()) m.monedaCode,
      ];

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
        'tasas': tasas,
        'monedas': monedas.map((m) => m.toJson()).toList(),
        if (tasasActualizadoEn != null)
          'tasasActualizadoEn': tasasActualizadoEn!.toIso8601String(),
      };

  factory MultimonedaConfig.fromCacheJson(Map<String, dynamic> json) {
    final monedasRaw = json['monedas'] as List<dynamic>? ?? [];
    DateTime? actualizado;
    final actualizadoRaw = json['tasasActualizadoEn'] as String?;
    if (actualizadoRaw != null) {
      actualizado = DateTime.tryParse(actualizadoRaw);
    }
    // Cache escrita por versiones anteriores: guardaban `tasasConversion`
    // (completo) y `tasasVigentes` (sin la moneda base). Se leen los tres
    // nombres y se unen para no invalidar la cache al actualizar la app.
    final tasas = <String, double>{};
    for (final key in const ['tasas', 'tasasConversion', 'tasasVigentes']) {
      final raw = json[key];
      if (raw is! Map) continue;
      raw.forEach((k, v) {
        if (k == 'CUP' || v is! num) return;
        final tasa = v.toDouble();
        if (tasa <= 0) return;
        tasas.putIfAbsent(k as String, () => tasa);
      });
    }
    return MultimonedaConfig(
      negocioId: json['negocioId'] as String? ?? '',
      monedaBase: json['monedaBase'] as String? ?? 'CUP',
      tasas: tasas,
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
