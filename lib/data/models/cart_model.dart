import 'dart:convert';

class CartItemModel {
  final String productoTiendaId;
  final String nombre;
  final double precio;
  final String? monedaPrecioCode;
  double cantidad;

  CartItemModel({
    required this.productoTiendaId,
    required this.nombre,
    required this.precio,
    this.monedaPrecioCode,
    this.cantidad = 1,
  });

  double get subtotal => precio * cantidad;

  Map<String, dynamic> toJson() => {
    'productoTiendaId': productoTiendaId,
    'nombre': nombre,
    'precio': precio,
    if (monedaPrecioCode != null) 'monedaPrecioCode': monedaPrecioCode,
    'cantidad': cantidad,
  };

  factory CartItemModel.fromJson(Map<String, dynamic> json) => CartItemModel(
    productoTiendaId: json['productoTiendaId'] as String,
    nombre: json['nombre'] as String,
    precio: (json['precio'] as num).toDouble(),
    monedaPrecioCode: json['monedaPrecioCode'] as String?,
    cantidad: (json['cantidad'] as num).toDouble(),
  );
}

class CartModel {
  final String id;
  String nombre;
  final List<CartItemModel> items;

  CartModel({
    required this.id,
    required this.nombre,
    List<CartItemModel>? items,
  }) : items = items ?? [];

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);
  int get itemCount => items.length;
  bool get isEmpty => items.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory CartModel.fromJson(Map<String, dynamic> json) => CartModel(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    items: (json['items'] as List<dynamic>)
        .map((i) => CartItemModel.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  /// Para SQLite
  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'itemsJson': jsonEncode(items.map((i) => i.toJson()).toList()),
  };

  factory CartModel.fromMap(Map<String, dynamic> map) {
    final itemsList = jsonDecode(map['itemsJson'] as String) as List;
    return CartModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      items: itemsList
          .map((i) => CartItemModel.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}
