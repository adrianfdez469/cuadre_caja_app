import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';
import '../../providers/venta_sin_stock_provider.dart';

/// Decide si el POS permite vender productos sin existencias.
///
/// Es el único origen del flag `permitirSinStock` que recorre
/// `ProductoPosRules` y las pantallas de venta: sin conexión siempre se
/// permite (la venta se valida al sincronizar), y con conexión solo si el
/// usuario activó el ajuste "Vender sin existencias".
class VentaSinStockPolicy {
  VentaSinStockPolicy._();

  /// [listen]: false para leerlo dentro de callbacks (equivale a `context.read`).
  static bool of(BuildContext context, {bool listen = true}) {
    final isOnline = Provider.of<SyncProvider>(context, listen: listen).isOnline;
    final ajuste =
        Provider.of<VentaSinStockProvider>(context, listen: listen).enabled;
    return !isOnline || ajuste;
  }
}
