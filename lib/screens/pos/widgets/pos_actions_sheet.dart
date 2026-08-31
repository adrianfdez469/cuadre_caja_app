import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/ventas_provider.dart';
import '../../../widgets/action_row.dart';
import '../../../widgets/sync_badge.dart';
import 'accounts_sheet.dart';
import '../productos_vendidos_screen.dart';
import '../punto_de_partida_screen.dart';
import '../ventas_list_screen.dart';

/// Hoja "Acciones del POS", abierta desde el botón "⋯" de la fila de
/// búsqueda. Reúne los accesos que antes vivían en el menú de la barra
/// superior, con el estilo de filas de `pos-mobile-estados.html` (Estado 1).
class PosActionsSheet {
  PosActionsSheet._();

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onSync,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PosActionsSheetContent(onSync: onSync),
    );
  }
}

class _PosActionsSheetContent extends StatelessWidget {
  final VoidCallback onSync;

  const _PosActionsSheetContent({required this.onSync});

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final cartProvider = context.watch<CartProvider>();
    final ventasProvider = context.watch<VentasProvider>();
    final errorCount = ventasProvider.errorCount;
    final porSubirCount = ventasProvider.porSubirCount;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Acciones del POS',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ActionRow(
                      icon: Icons.sync,
                      title: 'Sincronizar',
                      // Un rechazo del servidor manda sobre el último mensaje de
                      // sync: es lo que el cajero tiene que resolver.
                      subtitle: errorCount > 0
                          ? _plural(errorCount, 'venta con error',
                              'ventas con error')
                          : (syncProvider.lastMessage.isNotEmpty
                                ? syncProvider.lastMessage
                                : (syncProvider.isOnline
                                      ? 'Sincronizar ahora'
                                      : 'Sin conexión')),
                      trailing: CountBadge(
                        count: errorCount > 0 ? errorCount : porSubirCount,
                        tone: errorCount > 0
                            ? BadgeTone.error
                            : BadgeTone.pending,
                        semanticsLabel: _pendientesSemantics(
                          errorCount,
                          porSubirCount,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onSync();
                      },
                    ),
                    ActionRow(
                      icon: Icons.people_outline,
                      title: 'Cuentas abiertas',
                      subtitle:
                          '${cartProvider.cartCount} · activa "${cartProvider.activeCart?.nombre ?? '-'}"',
                      trailing: CountBadge(
                        count: cartProvider.cartCount > 1
                            ? cartProvider.cartCount
                            : 0,
                        tone: BadgeTone.accent,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        AccountsSheet.show(context);
                      },
                    ),
                    ActionRow(
                      icon: Icons.receipt_long,
                      title: 'Ventas y sincronizaciones',
                      subtitle: _ventasSubtitle(errorCount, porSubirCount),
                      iconColor: errorCount > 0 ? context.colors.negative : null,
                      trailing: CountBadge(
                        count: errorCount > 0 ? errorCount : porSubirCount,
                        tone: errorCount > 0
                            ? BadgeTone.error
                            : BadgeTone.pending,
                        semanticsLabel: _pendientesSemantics(
                          errorCount,
                          porSubirCount,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VentasListScreen(),
                          ),
                        );
                      },
                    ),
                    ActionRow(
                      icon: Icons.shopping_bag,
                      title: 'Productos Vendidos',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProductosVendidosScreen(),
                          ),
                        );
                      },
                    ),
                    ActionRow(
                      icon: Icons.flag,
                      title: 'Punto de partida',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PuntoDePartidaScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1 venta" / "2 ventas", sin dejar el singular en plural.
String _plural(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

/// Subtítulo de "Ventas y sincronizaciones": sólo aparece si hay algo que
/// contar, y nombra por separado lo que hay que revisar y lo que sólo espera.
String? _ventasSubtitle(int errorCount, int porSubirCount) {
  final partes = [
    if (errorCount > 0) '$errorCount con error',
    if (porSubirCount > 0) '$porSubirCount sin subir',
  ];
  return partes.isEmpty ? null : partes.join(' · ');
}

String? _pendientesSemantics(int errorCount, int porSubirCount) {
  if (errorCount > 0) {
    return _plural(errorCount, 'venta con error', 'ventas con error');
  }
  if (porSubirCount > 0) {
    return _plural(porSubirCount, 'venta sin subir', 'ventas sin subir');
  }
  return null;
}
