class UsuarioModel {
  final String id;
  final String nombre;
  final String usuario;
  final String? rol;
  final NegocioModel negocio;
  final TiendaModel localActual;
  final List<TiendaModel> locales;
  final List<String> permisos;

  UsuarioModel({
    required this.id,
    required this.nombre,
    required this.usuario,
    this.rol,
    required this.negocio,
    required this.localActual,
    required this.locales,
    required this.permisos,
  });

  factory UsuarioModel.fromJson(Map<String, dynamic> json) {
    final permisosRaw = json['permisos'];
    List<String> permisosList;
    if (permisosRaw is List) {
      permisosList = permisosRaw.map((e) => e.toString()).toList();
    } else if (permisosRaw is String) {
      permisosList = permisosRaw.isNotEmpty ? [permisosRaw] : [];
    } else {
      permisosList = [];
    }

    return UsuarioModel(
      id: json['id'] as String,
      nombre: json['nombre'] as String? ?? '',
      usuario: json['usuario'] as String? ?? '',
      rol: json['rol'] as String?,
      negocio: NegocioModel.fromJson(json['negocio'] as Map<String, dynamic>),
      localActual: TiendaModel.fromJson(json['localActual'] as Map<String, dynamic>),
      locales: (json['locales'] as List<dynamic>)
          .map((e) => TiendaModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      permisos: permisosList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'usuario': usuario,
    'rol': rol,
    'negocio': negocio.toJson(),
    'localActual': localActual.toJson(),
    'locales': locales.map((e) => e.toJson()).toList(),
    'permisos': permisos,
  };

  bool hasPermiso(String permiso) => permisos.contains(permiso);
}

class NegocioModel {
  final String id;
  final String nombre;
  final int userlimit;
  final String? limitTime;
  final int locallimit;
  final int productlimit;

  NegocioModel({
    required this.id,
    required this.nombre,
    required this.userlimit,
    this.limitTime,
    required this.locallimit,
    required this.productlimit,
  });

  factory NegocioModel.fromJson(Map<String, dynamic> json) => NegocioModel(
    id: json['id'] as String,
    nombre: json['nombre'] as String? ?? '',
    userlimit: (json['userlimit'] as num?)?.toInt() ?? 0,
    limitTime: json['limitTime'] as String?,
    locallimit: (json['locallimit'] as num?)?.toInt() ?? 0,
    productlimit: (json['productlimit'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'userlimit': userlimit,
    'limitTime': limitTime,
    'locallimit': locallimit,
    'productlimit': productlimit,
  };
}

class TiendaModel {
  final String id;
  final String nombre;
  final String negocioId;
  final String tipo;

  TiendaModel({
    required this.id,
    required this.nombre,
    required this.negocioId,
    required this.tipo,
  });

  factory TiendaModel.fromJson(Map<String, dynamic> json) => TiendaModel(
    id: json['id'] as String,
    nombre: json['nombre'] as String? ?? 'Sin nombre',
    negocioId: json['negocioId'] as String? ?? '',
    tipo: json['tipo'] as String? ?? 'TIENDA',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'negocioId': negocioId,
    'tipo': tipo,
  };
}
