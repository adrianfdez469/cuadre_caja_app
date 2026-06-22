import 'dart:convert';

import 'categoria_model.dart';

/// Convierte un valor que puede ser String o Map (objeto poblado del API) a String?.
/// Evita el error "type '_Map<String, dynamic>' is not a subtype of type 'String?'".
String? _stringOrMap(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is Map) {
    final v = value['nombre'] ?? value['descripcion'] ?? value['id'];
    if (v is String) return v;
    if (v != null) return v.toString();
  }
  return null;
}

String _stringOrMapRequired(dynamic value, [String fallback = '']) =>
    _stringOrMap(value) ?? value?.toString() ?? fallback;

class ProductoModel {
  final String id;             // ProductoTienda ID (usar para ventas)
  final String productoId;     // Producto base ID
  final String nombre;
  final String? descripcion;
  final double precio;
  final double costo;
  final String? monedaPrecioCode;
  final double existencia;
  final bool permiteDecimal;
  final CategoriaModel? categoria;
  final List<CodigoProductoModel> codigos;
  final String? proveedor;
  final bool esFraccion;
  final FraccionDeModel? fraccionDe;
  final int? unidadesPorFraccion;

  ProductoModel({
    required this.id,
    required this.productoId,
    required this.nombre,
    this.descripcion,
    required this.precio,
    required this.costo,
    this.monedaPrecioCode,
    required this.existencia,
    this.permiteDecimal = false,
    this.categoria,
    this.codigos = const [],
    this.proveedor,
    this.esFraccion = false,
    this.fraccionDe,
    this.unidadesPorFraccion,
  });

  bool get hasStock => existencia > 0;

  String get categoriaId => categoria?.id ?? '';
  String get categoriaNombre => categoria?.nombre ?? '';
  String get categoriaColor => categoria?.color ?? '#CCCCCC';

  factory ProductoModel.fromJson(Map<String, dynamic> json) {
    return ProductoModel(
      id: _stringOrMapRequired(json['id']),
      productoId: _stringOrMapRequired(json['productoId'], _stringOrMapRequired(json['id'])),
      nombre: _stringOrMapRequired(json['nombre'], 'Sin nombre'),
      descripcion: _stringOrMap(json['descripcion']),
      precio: (json['precio'] as num?)?.toDouble() ?? 0.0,
      costo: (json['costo'] as num?)?.toDouble() ?? 0.0,
      monedaPrecioCode: json['monedaPrecioCode'] as String?,
      existencia: (json['existencia'] as num?)?.toDouble() ?? 0.0,
      permiteDecimal: json['permiteDecimal'] as bool? ?? false,
      categoria: json['categoria'] != null
          ? CategoriaModel.fromJson(json['categoria'] as Map<String, dynamic>)
          : null,
      codigos: (json['codigos'] as List<dynamic>?)
              ?.map((c) => CodigoProductoModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      proveedor: _stringOrMap(json['proveedor']),
      esFraccion: json['esFraccion'] as bool? ?? false,
      fraccionDe: json['fraccionDe'] != null
          ? FraccionDeModel.fromJson(json['fraccionDe'] as Map<String, dynamic>)
          : null,
      unidadesPorFraccion: (json['unidadesPorFraccion'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'productoId': productoId,
    'nombre': nombre,
    'descripcion': descripcion,
    'precio': precio,
    'costo': costo,
    'monedaPrecioCode': monedaPrecioCode,
    'existencia': existencia,
    'permiteDecimal': permiteDecimal,
    'categoria': categoria?.toJson(),
    'codigos': codigos.map((c) => c.toJson()).toList(),
    'proveedor': proveedor,
    'esFraccion': esFraccion,
    'fraccionDe': fraccionDe?.toJson(),
    'unidadesPorFraccion': unidadesPorFraccion,
  };

  /// Para SQLite cache
  Map<String, dynamic> toMap() => {
    'id': id,
    'productoId': productoId,
    'nombre': nombre,
    'descripcion': descripcion,
    'precio': precio,
    'costo': costo,
    'monedaPrecioCode': monedaPrecioCode,
    'existencia': existencia,
    'permiteDecimal': permiteDecimal ? 1 : 0,
    'categoriaId': categoriaId,
    'categoriaNombre': categoriaNombre,
    'categoriaColor': categoriaColor,
    'proveedor': proveedor,
    'esFraccion': esFraccion ? 1 : 0,
    'fraccionDeId': fraccionDe?.id,
    'fraccionDeNombre': fraccionDe?.nombre,
    'unidadesPorFraccion': unidadesPorFraccion,
    'codigosJson': codigos.isEmpty ? null : jsonEncode(codigos.map((c) => c.toJson()).toList()),
  };

  factory ProductoModel.fromMap(Map<String, dynamic> map) {
    final codigosRaw = map['codigosJson'] as String?;
    List<CodigoProductoModel> codigosList = [];
    if (codigosRaw != null && codigosRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(codigosRaw) as List;
        codigosList = decoded.map((c) => CodigoProductoModel.fromJson(c as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    return ProductoModel(
      id: map['id'] as String,
      productoId: map['productoId'] as String? ?? map['id'] as String,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String?,
      precio: (map['precio'] as num).toDouble(),
      costo: (map['costo'] as num?)?.toDouble() ?? 0.0,
      existencia: (map['existencia'] as num?)?.toDouble() ?? 0.0,
      permiteDecimal: (map['permiteDecimal'] as int?) == 1,
      categoria: map['categoriaId'] != null
          ? CategoriaModel(
              id: map['categoriaId'] as String,
              nombre: map['categoriaNombre'] as String? ?? '',
              color: map['categoriaColor'] as String? ?? '#CCCCCC',
            )
          : null,
      proveedor: map['proveedor'] as String?,
      esFraccion: (map['esFraccion'] as int?) == 1,
      fraccionDe: map['fraccionDeId'] != null
          ? FraccionDeModel(
              id: map['fraccionDeId'] as String,
              nombre: map['fraccionDeNombre'] as String? ?? '',
            )
          : null,
      unidadesPorFraccion: map['unidadesPorFraccion'] as int?,
      monedaPrecioCode: map['monedaPrecioCode'] as String?,
      codigos: codigosList,
    );
  }
}

class CodigoProductoModel {
  final String id;
  final String codigo;
  final String? tipo;

  CodigoProductoModel({
    required this.id,
    required this.codigo,
    this.tipo,
  });

  factory CodigoProductoModel.fromJson(Map<String, dynamic> json) =>
      CodigoProductoModel(
        id: _stringOrMapRequired(json['id']),
        codigo: _stringOrMapRequired(json['codigo']),
        tipo: _stringOrMap(json['tipo']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'codigo': codigo,
    'tipo': tipo,
  };
}

class FraccionDeModel {
  final String id;
  final String nombre;

  FraccionDeModel({required this.id, required this.nombre});

  factory FraccionDeModel.fromJson(Map<String, dynamic> json) =>
      FraccionDeModel(
        id: _stringOrMap(json['id']) ?? '',
        nombre: _stringOrMap(json['nombre']) ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre};
}
