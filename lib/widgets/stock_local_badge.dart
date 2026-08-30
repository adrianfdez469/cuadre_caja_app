import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

/// Estilos compartidos para productos sin stock en la caché local.
///
/// Es un aviso, no un error: usa el tono `caution` del design system
/// ("todavía no es problema"), no `negative`.
class SinStockLocalStyles {
  SinStockLocalStyles._();

  static Color accent(BuildContext context) => context.colors.caution;
  static Color surface(BuildContext context) => context.colors.cautionWash;
  static Color border(BuildContext context) =>
      context.colors.caution.withValues(alpha: 0.45);
  static Color badgeBg(BuildContext context) => context.colors.cautionWash;

  static ShapeBorder cardShape(
    BuildContext context, {
    required bool sinStockLocal,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: sinStockLocal
          ? BorderSide(color: border(context), width: 1)
          : BorderSide.none,
    );
  }

  static Color? cardColor(BuildContext context, {required bool sinStockLocal}) {
    return sinStockLocal ? surface(context) : null;
  }
}

/// Badge para productos que se venden sin existencias.
///
/// Sin conexión el stock que falta es el de la caché ("Sin stock local", nube
/// tachada). Con conexión — el ajuste "Vender sin existencias" activo — el
/// stock que falta es el real del servidor, así que ni el "local" ni la nube
/// tachada aplican.
class StockLocalBadge extends StatelessWidget {
  final bool compact;
  final bool isOnline;

  const StockLocalBadge({super.key, this.compact = false, this.isOnline = false});

  @override
  Widget build(BuildContext context) {
    final label = isOnline
        ? (compact ? 'Sin stock' : 'SIN STOCK')
        : (compact ? 'Sin stock local' : 'SIN STOCK LOCAL');
    final iconSize = compact ? 11.0 : 14.0;
    final fontSize = compact ? 10.0 : 11.0;
    final hPad = compact ? 6.0 : 8.0;
    final vPad = compact ? 2.0 : 3.0;

    return Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: SinStockLocalStyles.badgeBg(context),
        borderRadius: BorderRadius.circular(compact ? AppRadius.sm : AppRadius.md),
        border: Border.all(color: SinStockLocalStyles.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOnline ? Icons.inventory_2_outlined : Icons.cloud_off_outlined,
            size: iconSize,
            color: SinStockLocalStyles.accent(context),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: SinStockLocalStyles.accent(context),
                letterSpacing: compact ? 0 : 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
