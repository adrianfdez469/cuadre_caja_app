import 'dart:convert';

import 'pago_multimoneda_model.dart';

/// Estado de sincronización de una venta local
enum SyncState { pending, syncing, synced, error }

/// Producto dentro de una venta (para enviar al API)
class VentaProducto {
  final String productoTiendaId;
  final double cantidad;
  final String? name;
  final double precio;

  VentaProducto({
    required this.productoTiendaId,
    required this.cantidad,
    this.name,
    required this.precio,
  });

  factory VentaProducto.fromJson(Map<String, dynamic> json) => VentaProducto(
    productoTiendaId: json['productoTiendaId'] as String? ?? '',
    cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
    name: json['name'] as String?,
    precio: (json['precio'] as num?)?.toDouble() ??
        (json['price'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'productoTiendaId': productoTiendaId,
    'cantidad': cantidad,
    'name': name,
    'precio': precio,
  };
}

/// Venta local (para almacenamiento offline y cola de sincronización)
class VentaLocalModel {
  final String syncId;
  final String tiendaId;
  final String periodoId;
  final List<VentaProducto> productos;
  final double total;
  final double totalcash;
  final double totaltransfer;
  final String? transferDestinationId;
  final bool wasOffline;
  final int syncAttempts;
  final int createdAt; // milliseconds
  final List<String>? discountCodes;
  final String monedaCobro;
  final List<PagoLinea> pagosDetalle;
  final List<VueltoLinea> vueltoDetalle;
  final Map<String, double> tasaSnapshot;
  final SyncState syncState;
  final String? errorMessage;
  final String? serverId;

  VentaLocalModel({
    required this.syncId,
    required this.tiendaId,
    required this.periodoId,
    required this.productos,
    required this.total,
    required this.totalcash,
    this.totaltransfer = 0,
    this.transferDestinationId,
    this.wasOffline = false,
    this.syncAttempts = 0,
    required this.createdAt,
    this.discountCodes,
    this.monedaCobro = VentaMultimonedaBuilder.monedaDefault,
    this.pagosDetalle = const [],
    this.vueltoDetalle = const [],
    this.tasaSnapshot = const {},
    this.syncState = SyncState.pending,
    this.errorMessage,
    this.serverId,
  });

  VentaLocalModel copyWith({
    SyncState? syncState,
    int? syncAttempts,
    String? errorMessage,
    String? serverId,
    String? monedaCobro,
    List<PagoLinea>? pagosDetalle,
    List<VueltoLinea>? vueltoDetalle,
    Map<String, double>? tasaSnapshot,
  }) => VentaLocalModel(
    syncId: syncId,
    tiendaId: tiendaId,
    periodoId: periodoId,
    productos: productos,
    total: total,
    totalcash: totalcash,
    totaltransfer: totaltransfer,
    transferDestinationId: transferDestinationId,
    wasOffline: wasOffline,
    syncAttempts: syncAttempts ?? this.syncAttempts,
    createdAt: createdAt,
    discountCodes: discountCodes,
    monedaCobro: monedaCobro ?? this.monedaCobro,
    pagosDetalle: pagosDetalle ?? this.pagosDetalle,
    vueltoDetalle: vueltoDetalle ?? this.vueltoDetalle,
    tasaSnapshot: tasaSnapshot ?? this.tasaSnapshot,
    syncState: syncState ?? this.syncState,
    errorMessage: errorMessage ?? this.errorMessage,
    serverId: serverId ?? this.serverId,
  );

  /// Body para POST /venta/{tiendaId}/{periodoId} (API v2 multimoneda).
  Map<String, dynamic> toApiJson() {
    final venta = VentaMultimonedaBuilder.ensureMultimoneda(
      this,
      tasaSnapshot: tasaSnapshot,
      monedaCobro: monedaCobro,
    );
    return {
      'syncId': venta.syncId,
      'createdAt': venta.createdAt,
      'productos': venta.productos.map((p) => p.toJson()).toList(),
      'total': venta.total,
      'totalcash': venta.totalcash,
      'totaltransfer': venta.totaltransfer,
      'transferDestinationId': venta.transferDestinationId,
      'wasOffline': venta.wasOffline,
      'syncAttempts': venta.syncAttempts,
      if (venta.discountCodes != null && venta.discountCodes!.isNotEmpty)
        'discountCodes': venta.discountCodes,
      'monedaCobro': venta.monedaCobro,
      'pagosDetalle': venta.pagosDetalle.map((p) => p.toJson()).toList(),
      'vueltoDetalle': venta.vueltoDetalle.map((v) => v.toJson()).toList(),
      'tasaSnapshot': venta.tasaSnapshot,
    };
  }

  /// Para SQLite
  Map<String, dynamic> toMap() => {
    'syncId': syncId,
    'tiendaId': tiendaId,
    'periodoId': periodoId,
    'productosJson': jsonEncode(productos.map((p) => p.toJson()).toList()),
    'total': total,
    'totalcash': totalcash,
    'totaltransfer': totaltransfer,
    'transferDestinationId': transferDestinationId,
    'wasOffline': wasOffline ? 1 : 0,
    'syncAttempts': syncAttempts,
    'createdAt': createdAt,
    'discountCodes': discountCodes != null ? jsonEncode(discountCodes) : null,
    'monedaCobro': monedaCobro,
    'pagosDetalleJson': pagosDetalle.isEmpty
        ? null
        : jsonEncode(pagosDetalle.map((p) => p.toJson()).toList()),
    'vueltoDetalleJson': vueltoDetalle.isEmpty
        ? null
        : jsonEncode(vueltoDetalle.map((v) => v.toJson()).toList()),
    'tasaSnapshotJson': tasaSnapshot.isEmpty ? null : jsonEncode(tasaSnapshot),
    'syncState': syncState.name,
    'errorMessage': errorMessage,
    'serverId': serverId,
  };

  factory VentaLocalModel.fromMap(Map<String, dynamic> map) {
    final productosJson = jsonDecode(map['productosJson'] as String) as List;
    final discountCodesRaw = map['discountCodes'] as String?;
    final pagosRaw = map['pagosDetalleJson'] as String?;
    final vueltoRaw = map['vueltoDetalleJson'] as String?;
    final tasaRaw = map['tasaSnapshotJson'] as String?;

    List<PagoLinea> pagos = [];
    if (pagosRaw != null && pagosRaw.isNotEmpty) {
      final decoded = jsonDecode(pagosRaw) as List;
      pagos = decoded
          .map((p) => PagoLinea.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    List<VueltoLinea> vuelto = [];
    if (vueltoRaw != null && vueltoRaw.isNotEmpty) {
      final decoded = jsonDecode(vueltoRaw) as List;
      vuelto = decoded
          .map((v) => VueltoLinea.fromJson(v as Map<String, dynamic>))
          .toList();
    }

    Map<String, double> tasaSnapshot = {};
    if (tasaRaw != null && tasaRaw.isNotEmpty) {
      final decoded = jsonDecode(tasaRaw) as Map<String, dynamic>;
      tasaSnapshot = decoded.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );
    }

    return VentaLocalModel(
      syncId: map['syncId'] as String,
      tiendaId: map['tiendaId'] as String,
      periodoId: map['periodoId'] as String,
      productos: productosJson
          .map((p) => VentaProducto.fromJson(p as Map<String, dynamic>))
          .toList(),
      total: (map['total'] as num).toDouble(),
      totalcash: (map['totalcash'] as num).toDouble(),
      totaltransfer: (map['totaltransfer'] as num?)?.toDouble() ?? 0,
      transferDestinationId: map['transferDestinationId'] as String?,
      wasOffline: (map['wasOffline'] as int) == 1,
      syncAttempts: map['syncAttempts'] as int? ?? 0,
      createdAt: map['createdAt'] as int,
      discountCodes: discountCodesRaw != null
          ? (jsonDecode(discountCodesRaw) as List).cast<String>()
          : null,
      monedaCobro: map['monedaCobro'] as String? ??
          VentaMultimonedaBuilder.monedaDefault,
      pagosDetalle: pagos,
      vueltoDetalle: vuelto,
      tasaSnapshot: tasaSnapshot,
      syncState: SyncState.values.firstWhere(
        (e) => e.name == (map['syncState'] as String? ?? 'pending'),
        orElse: () => SyncState.pending,
      ),
      errorMessage: map['errorMessage'] as String?,
      serverId: map['serverId'] as String?,
    );
  }
}

/// Construye payloads multimoneda (migración CUP-only y cobro actual).
class VentaMultimonedaBuilder {
  VentaMultimonedaBuilder._();

  static const String monedaDefault = 'CUP';

  static List<PagoLinea> buildPagosCupOnly({
    required double totalcash,
    required double totaltransfer,
    String? transferDestinationId,
    String moneda = monedaDefault,
  }) {
    final pagos = <PagoLinea>[];
    if (totalcash > 0) {
      pagos.add(PagoLinea(
        tipo: 'cash',
        moneda: moneda,
        monto: totalcash,
        equivalenteBase: totalcash,
      ));
    }
    if (totaltransfer > 0) {
      pagos.add(PagoLinea(
        tipo: 'transfer',
        moneda: moneda,
        monto: totaltransfer,
        equivalenteBase: totaltransfer,
        transferDestinationId: transferDestinationId,
      ));
    }
    return pagos;
  }

  static List<VueltoLinea> buildVueltoCupOnly(
    double cambio, {
    String moneda = monedaDefault,
  }) {
    if (cambio <= 0) return [];
    return [VueltoLinea(moneda: moneda, monto: cambio)];
  }

  /// Rellena campos multimoneda faltantes (ventas pendientes pre-v2).
  static VentaLocalModel ensureMultimoneda(
    VentaLocalModel venta, {
    Map<String, double>? tasaSnapshot,
    String monedaCobro = monedaDefault,
  }) {
    if (venta.pagosDetalle.isNotEmpty) return venta;

    final pagos = buildPagosCupOnly(
      totalcash: venta.totalcash,
      totaltransfer: venta.totaltransfer,
      transferDestinationId: venta.transferDestinationId,
      moneda: monedaCobro,
    );

    if (pagos.isEmpty && venta.total > 0) {
      pagos.add(PagoLinea(
        tipo: 'cash',
        moneda: monedaCobro,
        monto: venta.total,
        equivalenteBase: venta.total,
      ));
    }

    return venta.copyWith(
      monedaCobro: monedaCobro,
      pagosDetalle: pagos,
      vueltoDetalle: const [],
      tasaSnapshot: tasaSnapshot ?? const {},
    );
  }
}

/// Venta recibida del servidor
class VentaServerModel {
  final String id;
  final String tiendaId;
  final String usuarioId;
  final String cierrePeriodoId;
  final double total;
  final double totalcash;
  final double totaltransfer;
  final double discountTotal;
  final String? syncId;
  final DateTime createdAt;
  final DateTime? frontendCreatedAt;
  final bool wasOffline;
  final String? usuarioNombre;
  final List<VentaProducto> productos;
  final String? transferDestinationId;
  final String? transferDestinationNombre;

  VentaServerModel({
    required this.id,
    required this.tiendaId,
    required this.usuarioId,
    required this.cierrePeriodoId,
    required this.total,
    required this.totalcash,
    this.totaltransfer = 0,
    this.discountTotal = 0,
    this.syncId,
    required this.createdAt,
    this.frontendCreatedAt,
    this.wasOffline = false,
    this.usuarioNombre,
    required this.productos,
    this.transferDestinationId,
    this.transferDestinationNombre,
  });

  /// Parsea respuesta de GET /api/app/venta/{tiendaId}/{periodoId} (y detalle).
  /// Cada venta puede incluir: transferDestinationId (id si aplica) y/o
  /// transferDestination: { id, nombre } (objeto si aplica, o undefined si no tiene destino).
  factory VentaServerModel.fromJson(Map<String, dynamic> json) {
    final transferDest = json['transferDestination'] as Map<String, dynamic>?;
    final transferId = transferDest?['id'] as String? ?? json['transferDestinationId'] as String?;
    final transferNombre = transferDest?['nombre'] as String?;

    return VentaServerModel(
      id: json['id'] as String,
      tiendaId: json['tiendaId'] as String? ?? '',
      usuarioId: json['usuarioId'] as String? ?? '',
      cierrePeriodoId: json['cierrePeriodoId'] as String? ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      totalcash: (json['totalcash'] as num?)?.toDouble() ?? 0,
      totaltransfer: (json['totaltransfer'] as num?)?.toDouble() ?? 0,
      discountTotal: (json['discountTotal'] as num?)?.toDouble() ?? 0,
      syncId: json['syncId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      frontendCreatedAt: json['frontendCreatedAt'] != null
          ? DateTime.parse(json['frontendCreatedAt'] as String)
          : null,
      wasOffline: json['wasOffline'] as bool? ?? false,
      usuarioNombre: (json['usuario']?['nombre'] as String?) ??
          json['usuarioNombre'] as String?,
      productos: (json['productos'] as List<dynamic>?)
              ?.map((p) => VentaProducto.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      transferDestinationId: transferId,
      transferDestinationNombre: transferNombre,
    );
  }

  /// Serialización para cache local (no tiene que coincidir 1:1 con el API).
  Map<String, dynamic> toJson() => {
        'id': id,
        'tiendaId': tiendaId,
        'usuarioId': usuarioId,
        'cierrePeriodoId': cierrePeriodoId,
        'total': total,
        'totalcash': totalcash,
        'totaltransfer': totaltransfer,
        'discountTotal': discountTotal,
        'syncId': syncId,
        'createdAt': createdAt.toIso8601String(),
        if (frontendCreatedAt != null)
          'frontendCreatedAt': frontendCreatedAt!.toIso8601String(),
        'wasOffline': wasOffline,
        'usuarioNombre': usuarioNombre,
        'productos': productos.map((p) => p.toJson()).toList(),
      };
}

/// Modelo unificado para listado y detalle (servidor + local)
class VentaUnificadaModel {
  final String identifier;
  final String? dbId;
  final String tiendaId;
  final String periodoId;
  final double total;
  final double totalcash;
  final double totaltransfer;
  final double discountTotal;
  final int createdAtMs;
  final bool synced;
  final SyncState syncState;
  final bool wasOffline;
  final int syncAttempts;
  final String? errorMessage;
  /// ID del usuario que realizó la venta (servidor); null en ventas locales = usuario actual.
  final String? usuarioId;
  final String? usuarioNombre;
  final List<VentaProducto> productos;
  /// ID del destino de transferencia si la venta incluyó pago por transferencia.
  final String? transferDestinationId;
  /// Nombre del destino (resuelto desde API o destinos cargados).
  final String? transferDestinationNombre;

  VentaUnificadaModel({
    required this.identifier,
    this.dbId,
    required this.tiendaId,
    required this.periodoId,
    required this.total,
    required this.totalcash,
    this.totaltransfer = 0,
    this.discountTotal = 0,
    required this.createdAtMs,
    required this.synced,
    required this.syncState,
    this.wasOffline = false,
    this.syncAttempts = 0,
    this.errorMessage,
    this.usuarioId,
    this.usuarioNombre,
    required this.productos,
    this.transferDestinationId,
    this.transferDestinationNombre,
  });

  int get itemCount => productos.length;

  static VentaUnificadaModel fromLocal(VentaLocalModel v) => VentaUnificadaModel(
        identifier: v.syncId,
        dbId: v.serverId,
        tiendaId: v.tiendaId,
        periodoId: v.periodoId,
        total: v.total,
        totalcash: v.totalcash,
        totaltransfer: v.totaltransfer,
        discountTotal: 0,
        createdAtMs: v.createdAt,
        synced: v.syncState == SyncState.synced,
        syncState: v.syncState,
        wasOffline: v.wasOffline,
        syncAttempts: v.syncAttempts,
        errorMessage: v.errorMessage,
        usuarioId: null,
        usuarioNombre: null,
        productos: v.productos,
        transferDestinationId: v.transferDestinationId,
        transferDestinationNombre: null,
      );

  static VentaUnificadaModel fromServer(VentaServerModel v) => VentaUnificadaModel(
        identifier: v.syncId ?? v.id,
        dbId: v.id,
        tiendaId: v.tiendaId,
        periodoId: v.cierrePeriodoId,
        total: v.total,
        totalcash: v.totalcash,
        totaltransfer: v.totaltransfer,
        discountTotal: v.discountTotal,
        createdAtMs: (v.frontendCreatedAt ?? v.createdAt).millisecondsSinceEpoch,
        synced: true,
        syncState: SyncState.synced,
        wasOffline: v.wasOffline,
        syncAttempts: 0,
        usuarioId: v.usuarioId,
        usuarioNombre: v.usuarioNombre,
        productos: v.productos,
        transferDestinationId: v.transferDestinationId,
        transferDestinationNombre: v.transferDestinationNombre,
      );
}
