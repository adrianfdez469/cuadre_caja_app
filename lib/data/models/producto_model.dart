import 'categoria_model.dart';

class ProductoModel {
  final String id;             // ProductoTienda ID (usar para ventas)
  final String productoId;     // Producto base ID
  final String nombre;
  final String? descripcion;
  final double precio;
  final double costo;
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
      id: json['id'] as String? ?? '',
      productoId: json['productoId'] as String? ?? json['id'] as String? ?? '',
      nombre: json['nombre'] as String? ?? 'Sin nombre',
      descripcion: json['descripcion'] as String?,
      precio: (json['precio'] as num?)?.toDouble() ?? 0.0,
      costo: (json['costo'] as num?)?.toDouble() ?? 0.0,
      existencia: (json['existencia'] as num?)?.toDouble() ?? 0.0,
      permiteDecimal: json['permiteDecimal'] as bool? ?? false,
      categoria: json['categoria'] != null
          ? CategoriaModel.fromJson(json['categoria'] as Map<String, dynamic>)
          : null,
      codigos: (json['codigos'] as List<dynamic>?)
              ?.map((c) => CodigoProductoModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      proveedor: json['proveedor'] as String?,
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
  };

  factory ProductoModel.fromMap(Map<String, dynamic> map) => ProductoModel(
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
  );
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
        id: json['id'] as String? ?? '',
        codigo: json['codigo'] as String? ?? '',
        tipo: json['tipo'] as String?,
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
        id: json['id'] as String? ?? '',
        nombre: json['nombre'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre};
}
