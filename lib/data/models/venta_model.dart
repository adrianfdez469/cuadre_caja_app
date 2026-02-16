import 'dart:convert';

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
    this.syncState = SyncState.pending,
    this.errorMessage,
    this.serverId,
  });

  VentaLocalModel copyWith({
    SyncState? syncState,
    int? syncAttempts,
    String? errorMessage,
    String? serverId,
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
    syncState: syncState ?? this.syncState,
    errorMessage: errorMessage ?? this.errorMessage,
    serverId: serverId ?? this.serverId,
  );

  /// Body para POST /venta/{tiendaId}/{periodoId}
  Map<String, dynamic> toApiJson() => {
    'syncId': syncId,
    'createdAt': createdAt,
    'productos': productos.map((p) => p.toJson()).toList(),
    'total': total,
    'totalcash': totalcash,
    'totaltransfer': totaltransfer,
    'transferDestinationId': transferDestinationId,
    'wasOffline': wasOffline,
    'syncAttempts': syncAttempts,
    if (discountCodes != null && discountCodes!.isNotEmpty)
      'discountCodes': discountCodes,
  };

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
    'syncState': syncState.name,
    'errorMessage': errorMessage,
    'serverId': serverId,
  };

  factory VentaLocalModel.fromMap(Map<String, dynamic> map) {
    final productosJson = jsonDecode(map['productosJson'] as String) as List;
    final discountCodesRaw = map['discountCodes'] as String?;

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
      syncState: SyncState.values.firstWhere(
        (e) => e.name == (map['syncState'] as String? ?? 'pending'),
        orElse: () => SyncState.pending,
      ),
      errorMessage: map['errorMessage'] as String?,
      serverId: map['serverId'] as String?,
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
  });

  factory VentaServerModel.fromJson(Map<String, dynamic> json) {
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
      usuarioNombre: json['usuario']?['nombre'] as String?,
      productos: (json['productos'] as List<dynamic>?)
              ?.map((p) => VentaProducto.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
