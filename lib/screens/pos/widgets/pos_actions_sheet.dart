import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../version_screen.dart';
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
    required VoidCallback onLogout,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _PosActionsSheetContent(onSync: onSync, onLogout: onLogout),
    );
  }
}

class _PosActionsSheetContent extends StatelessWidget {
  final VoidCallback onSync;
  final VoidCallback onLogout;

  const _PosActionsSheetContent({required this.onSync, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final syncProvider = context.watch<SyncProvider>();
    final cartProvider = context.watch<CartProvider>();

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
                    _ActionRow(
                      icon: Icons.sync,
                      title: 'Sincronizar',
                      subtitle: syncProvider.lastMessage.isNotEmpty
                          ? syncProvider.lastMessage
                          : (syncProvider.isOnline
                                ? 'Sincronizar ahora'
                                : 'Sin conexión'),
                      onTap: () {
                        Navigator.pop(context);
                        onSync();
                      },
                    ),
                    _ActionRow(
                      icon: Icons.people_outline,
                      title: 'Cuentas abiertas',
                      subtitle:
                          '${cartProvider.cartCount} · activa "${cartProvider.activeCart?.nombre ?? '-'}"',
                      trailing: cartProvider.cartCount > 1
                          ? _CountBadge(
                              count: cartProvider.cartCount,
                              colors: colors,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        AccountsSheet.show(context);
                      },
                    ),
                    _ActionRow(
                      icon: Icons.receipt_long,
                      title: 'Ventas y sincronizaciones',
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
                    _ActionRow(
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
                    _ActionRow(
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
                    _ActionRow(
                      icon: Icons.info_outline,
                      title: 'Versión',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VersionScreen(),
                          ),
                        );
                      },
                    ),
                    _ActionRow(
                      icon: Icons.logout,
                      title: 'Cerrar sesión',
                      iconColor: colors.negative,
                      onTap: () {
                        Navigator.pop(context);
                        onLogout();
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

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.sunken,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor ?? colors.textPrimary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final AppSemanticColors colors;

  const _CountBadge({required this.count, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.accentWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: colors.accent,
        ),
      ),
    );
  }
}
