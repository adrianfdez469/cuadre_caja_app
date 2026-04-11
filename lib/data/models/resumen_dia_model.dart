class ResumenDiaTotales {
  final double ventas;
  final double entradas;
  final double salidas;

  const ResumenDiaTotales({
    required this.ventas,
    required this.entradas,
    required this.salidas,
  });

  factory ResumenDiaTotales.fromJson(Map<String, dynamic> json) {
    return ResumenDiaTotales(
      ventas: (json['ventas'] as num?)?.toDouble() ?? 0.0,
      entradas: (json['entradas'] as num?)?.toDouble() ?? 0.0,
      salidas: (json['salidas'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ResumenDiaProducto {
  final String productoTiendaId;
  final String productoId;
  final String nombre;
  final String? proveedorNombre;
  final bool permiteDecimal;
  final String? categoriaId;
  final String? categoriaNombre;
  final String? categoriaColor;
  final bool tieneMovimientos;
  final DateTime? ultimaModificacion;
  final double cantidadInicial;
  final double ventas;
  final double entradas;
  final double salidas;
  final double cantidadFinal;

  const ResumenDiaProducto({
    required this.productoTiendaId,
    required this.productoId,
    required this.nombre,
    this.proveedorNombre,
    required this.permiteDecimal,
    this.categoriaId,
    this.categoriaNombre,
    this.categoriaColor,
    required this.tieneMovimientos,
    this.ultimaModificacion,
    required this.cantidadInicial,
    required this.ventas,
    required this.entradas,
    required this.salidas,
    required this.cantidadFinal,
  });

  factory ResumenDiaProducto.fromJson(Map<String, dynamic> json) {
    return ResumenDiaProducto(
      productoTiendaId: json['productoTiendaId'] as String,
      productoId: json['productoId'] as String,
      nombre: json['nombre'] as String,
      proveedorNombre: json['proveedorNombre'] as String?,
      permiteDecimal: json['permiteDecimal'] as bool? ?? false,
      categoriaId: json['categoriaId'] as String?,
      categoriaNombre: json['categoriaNombre'] as String?,
      categoriaColor: json['categoriaColor'] as String?,
      tieneMovimientos: json['tieneMovimientos'] as bool? ?? false,
      ultimaModificacion: json['ultimaModificacion'] != null
          ? DateTime.tryParse(json['ultimaModificacion'] as String)
          : null,
      cantidadInicial: (json['cantidadInicial'] as num?)?.toDouble() ?? 0.0,
      ventas: (json['ventas'] as num?)?.toDouble() ?? 0.0,
      entradas: (json['entradas'] as num?)?.toDouble() ?? 0.0,
      salidas: (json['salidas'] as num?)?.toDouble() ?? 0.0,
      cantidadFinal: (json['cantidadFinal'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ResumenDiaModel {
  final ResumenDiaTotales totales;
  final List<ResumenDiaProducto> productos;

  const ResumenDiaModel({
    required this.totales,
    required this.productos,
  });

  factory ResumenDiaModel.fromJson(Map<String, dynamic> json) {
    return ResumenDiaModel(
      totales: ResumenDiaTotales.fromJson(
        json['totales'] as Map<String, dynamic>,
      ),
      productos: (json['productos'] as List<dynamic>)
          .map((e) => ResumenDiaProducto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
