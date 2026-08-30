import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../providers/theme_mode_provider.dart';
import '../../../providers/venta_sin_stock_provider.dart';
import '../../../widgets/action_row.dart';
import '../../version_screen.dart';

/// Hoja "Cuenta", abierta desde el avatar del usuario en la barra superior.
/// Reúne lo que es del usuario/dispositivo (modo oscuro, venta sin existencias,
/// versión, cerrar sesión), separado de "Acciones del POS" (⋯), que es sobre la
/// operación de venta.
class UserMenuSheet {
  UserMenuSheet._();

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onLogout,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserMenuSheetContent(onLogout: onLogout),
    );
  }
}

class _UserMenuSheetContent extends StatelessWidget {
  final VoidCallback onLogout;

  const _UserMenuSheetContent({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final themeModeProvider = context.watch<ThemeModeProvider>();
    final ventaSinStock = context.watch<VentaSinStockProvider>();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Cuenta',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ActionRow(
            icon: themeModeProvider.isDarkMode
                ? Icons.dark_mode
                : Icons.light_mode_outlined,
            title: 'Modo oscuro',
            subtitle: themeModeProvider.isDarkMode ? 'Activado' : 'Desactivado',
            trailing: Switch(
              value: themeModeProvider.isDarkMode,
              activeTrackColor: colors.accent,
              onChanged: (v) => themeModeProvider.setDarkMode(v),
            ),
            onTap: () => themeModeProvider.setDarkMode(!themeModeProvider.isDarkMode),
          ),
          ActionRow(
            icon: Icons.production_quantity_limits,
            title: 'Vender sin existencias',
            subtitle: ventaSinStock.enabled
                ? 'Activado — el servidor puede rechazar la venta'
                : 'Solo sin conexión',
            trailing: Switch(
              value: ventaSinStock.enabled,
              activeTrackColor: colors.accent,
              onChanged: (v) => ventaSinStock.setEnabled(v),
            ),
            onTap: () => ventaSinStock.setEnabled(!ventaSinStock.enabled),
          ),
          ActionRow(
            icon: Icons.info_outline,
            title: 'Versión',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VersionScreen()),
              );
            },
          ),
          ActionRow(
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
    );
  }
}
