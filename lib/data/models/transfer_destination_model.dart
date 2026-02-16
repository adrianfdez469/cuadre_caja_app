class TransferDestinationModel {
  final String id;
  final String nombre;
  final String? descripcion;
  final bool isDefault;

  TransferDestinationModel({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.isDefault = false,
  });

  factory TransferDestinationModel.fromJson(Map<String, dynamic> json) =>
      TransferDestinationModel(
        id: json['id'] as String,
        nombre: json['nombre'] as String? ?? '',
        descripcion: json['descripcion'] as String?,
        isDefault: json['default'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'descripcion': descripcion,
    'default': isDefault,
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'descripcion': descripcion,
    'isDefault': isDefault ? 1 : 0,
  };

  factory TransferDestinationModel.fromMap(Map<String, dynamic> map) =>
      TransferDestinationModel(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
        descripcion: map['descripcion'] as String?,
        isDefault: (map['isDefault'] as int?) == 1,
      );
}
