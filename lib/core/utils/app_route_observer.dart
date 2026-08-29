import 'package:flutter/widgets.dart';

/// Observer de navegación global, registrado en el `MaterialApp`.
///
/// Lo usa la pantalla de venta (via `RouteAware`) para enterarse de cuándo le
/// abren algo encima y soltar el foco del buscador: si no, al cerrar esa ruta
/// Flutter restaura el foco anterior y el teclado se levanta solo.
///
/// El parámetro de tipo es `Route<dynamic>` (y no `ModalRoute<void>`, como en
/// el ejemplo de la documentación) para que también notifique con rutas de
/// modales, diálogos y menús emergentes, cuyo tipo genérico varía.
final RouteObserver<Route<dynamic>> appRouteObserver =
    RouteObserver<Route<dynamic>>();
