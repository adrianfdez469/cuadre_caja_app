class CategoriaModel {
  final String id;
  final String nombre;
  final String color;

  CategoriaModel({
    required this.id,
    required this.nombre,
    required this.color,
  });

  factory CategoriaModel.fromJson(Map<String, dynamic> json) => CategoriaModel(
    id: json['id'] as String? ?? '',
    nombre: json['nombre'] as String? ?? 'Sin nombre',
    color: json['color'] as String? ?? '#CCCCCC',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'color': color,
  };

  Map<String, dynamic> toMap() => toJson();

  factory CategoriaModel.fromMap(Map<String, dynamic> map) =>
      CategoriaModel.fromJson(map);
}
